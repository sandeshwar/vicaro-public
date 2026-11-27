#!/bin/sh
# Vicaro helper installer (macOS & Linux). Reads like a script, because you should read it:
#   curl -fsSL https://vicaro.creativeducks.com/install.sh | sh
#
# What it does, in order:
#   macOS: download the app tarball, verify its SHA-256, replace
#          ~/Applications/Vicaro Helper.app, register the LaunchAgent, and start it.
#   Linux: download the Linux tarball, verify its SHA-256, install into
#          ~/.local/share/vicaro/app, link ~/.local/bin/vicaro-helper, register
#          the systemd --user service, XDG autostart tray agent and vicaro://
#          desktop handler, and start the helper.
#
# It does not install the Chrome extension: Vicaro Beta comes from the Chrome Web
# Store. MCP host wiring is done later from the helper web console, not by this installer.
#
#   --no-agent       do not register the login agent / systemd user service
#   --no-extension   accepted for older commands; this build never stages one
#   --mcp            accepted for older commands; not used by this build
#   --no-open        accepted for older commands; this build opens nothing
#   --dry-run        print what would happen, change nothing
set -eu

APP_NAME="Vicaro Helper"
STORE_URL="https://chromewebstore.google.com/detail/vicaro-beta/inemnoeadlodgmheeijooeknmladelok"
# Where the tarball and its .sha256 live: the GitHub Release on vicaro-public.
# Free, CDN-backed, and it keeps install traffic away from the site's bandwidth.
# There is no mirror - the release is the only source, so a failed fetch is fatal.
BASE_URL="${VICARO_BASE_URL:-https://github.com/sandeshwar/vicaro-public/releases/latest/download}"

NO_AGENT=0
WANT_MCP=0
DRY=0
for arg in "$@"; do
  case "$arg" in
    --no-agent) NO_AGENT=1 ;;
    --mcp) WANT_MCP=1 ;;
    --no-mcp) WANT_MCP=0 ;;
    --no-extension|--no-open) ;;
    --dry-run) DRY=1 ;;
    *) echo "unknown option: $arg (use --no-agent, --dry-run)" >&2; exit 2 ;;
  esac
done

OS_RAW="$(uname -s)"
ARCH_RAW="$(uname -m)"
case "$OS_RAW" in
  Darwin)
    OS="macos"
    case "$ARCH_RAW" in
      arm64|x86_64) ARCH="$ARCH_RAW" ;;
      *) echo "unsupported architecture: $ARCH_RAW" >&2; exit 1 ;;
    esac
    TARBALL="Vicaro-macos-$ARCH.tar.gz"
    DEST="$HOME/Applications"
    APP="$DEST/$APP_NAME.app"
    ;;
  Linux)
    OS="linux"
    case "$ARCH_RAW" in
      x86_64|amd64) ARCH="x86_64" ;;
      aarch64|arm64) ARCH="aarch64" ;;
      *) echo "unsupported Linux architecture: $ARCH_RAW (supported: x86_64, aarch64)" >&2; exit 1 ;;
    esac
    TARBALL="Vicaro-linux-$ARCH.tar.gz"
    XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
    XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
    XDG_STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
    APP="$XDG_DATA/vicaro/app"
    BIN_DIR="$HOME/.local/bin"
    ;;
  *)
    echo "unsupported OS: $OS_RAW (supported: macOS, Linux; Windows support is coming soon)" >&2
    exit 1
    ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- progress ----
# 40 MB on a slow line looks frozen, so the tarball fetch draws a bar. Everything
# here is skipped when stderr is not a terminal (CI, logs, `| tee`), where the
# carriage returns would be noise.
TTY=0
[ -t 2 ] && TTY=1
BAR=30
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) FILL='█'; EMPTY='░' ;;
  *) FILL='#'; EMPTY='-' ;;
esac

human() { # bytes -> "38.6 MB"
  awk -v b="${1:-0}" 'BEGIN {
    split("B KB MB GB TB", u, " "); i = 1
    while (b >= 1000 && i < 5) { b /= 1000; i++ }
    printf(i == 1 ? "%d %s" : "%.1f %s", b, u[i])
  }' /dev/null
}

draw() { # have total elapsed
  awk -v have="${1:-0}" -v total="${2:-0}" -v secs="${3:-0}" \
      -v w="$BAR" -v f="$FILL" -v e="$EMPTY" '
    function hum(b) {
      split("B KB MB GB TB", u, " "); i = 1
      while (b >= 1000 && i < 5) { b /= 1000; i++ }
      return (i == 1) ? sprintf("%d %s", b, u[i]) : sprintf("%.1f %s", b, u[i])
    }
    BEGIN {
      # Without a Content-Length there is nothing to fill, so show bytes only
      # rather than a bar that never leaves zero.
      if (total <= 0) {
        line = hum(have)
      } else {
        pct = int(have * 100 / total)
        if (pct > 100) pct = 100
        n = int(pct * w / 100)
        bar = ""
        for (i = 0; i < n; i++) bar = bar f
        for (; i < w; i++) bar = bar e
        line = sprintf("[%s] %3d%%  %s / %s", bar, pct, hum(have), hum(total))
      }
      # A rate measured over one second is an average of the whole download, so it
      # jumps around; it only means something once the transfer has run a while.
      if (secs >= 2 && have > 0) line = line sprintf("  %s/s", hum(have / secs))
      printf "\r  %s\033[K", line
    }' /dev/null
}

fetch() { # url dest label - returns non-zero if the download did not happen
  f_url="$1" f_dest="$2" f_label="$3"
  # Ask for the size first so the bar is determinate from the first frame.
  f_total="$(curl -fsIL "$f_url" 2>/dev/null | tr -d '\r' |
    awk 'tolower($1) == "content-length:" { n = $2 } END { print n + 0 }')"

  if [ "$TTY" != "1" ]; then
    echo "  fetching $f_label ($(human "$f_total"))"
    curl -fsSL "$f_url" -o "$f_dest" && return 0
    return 1
  fi

  echo "  fetching $f_label ($(human "$f_total"))"
  rm -f "$TMP/.rc"
  : > "$f_dest"
  # A flag file, not `kill -0`: it cleanly separates "curl is still writing" from
  # "curl finished" and carries the exit status back out of the subshell.
  ( curl -fsSL "$f_url" -o "$f_dest" 2>/dev/null; echo $? > "$TMP/.rc" ) &
  f_pid=$!
  f_start="$(date +%s)"
  while [ ! -f "$TMP/.rc" ]; do
    f_have="$(wc -c < "$f_dest" 2>/dev/null | tr -d ' ')"
    draw "${f_have:-0}" "$f_total" "$(( $(date +%s) - f_start ))" >&2
    sleep 0.2
  done
  wait "$f_pid" 2>/dev/null || true
  f_rc="$(cat "$TMP/.rc")"
  # Only finish the bar on success: a failed transfer ends on a partial bar,
  # which would read as "done".
  if [ "$f_rc" = "0" ]; then
    f_have="$(wc -c < "$f_dest" 2>/dev/null | tr -d ' ')"
    draw "${f_have:-0}" "$f_total" "$(( $(date +%s) - f_start ))" >&2
  fi
  printf '\n' >&2
  [ "$f_rc" = "0" ]
}

echo "Vicaro installer"
echo "  target: $APP"

# ---- fetch ----
if [ -n "${VICARO_TARBALL:-}" ]; then
  cp "$VICARO_TARBALL" "$TMP/app.tar.gz"
  [ -f "$VICARO_TARBALL.sha256" ] && cp "$VICARO_TARBALL.sha256" "$TMP/app.sha256"
else
  if ! fetch "$BASE_URL/$TARBALL" "$TMP/app.tar.gz" "$TARBALL"; then
    if [ "$OS" = "macos" ]; then
      WANTED="$TARBALL"
      TARBALL="Vicaro-macos-universal.tar.gz"
      echo "  no $WANTED for this Mac - trying $TARBALL"
      fetch "$BASE_URL/$TARBALL" "$TMP/app.tar.gz" "$TARBALL"
    else
      echo "could not download $TARBALL from $BASE_URL" >&2
      exit 1
    fi
  fi
  curl -fsSL "$BASE_URL/$TARBALL.sha256" -o "$TMP/app.sha256"
fi

# ---- verify ----
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    echo "neither sha256sum nor shasum found" >&2
    exit 1
  fi
}

if [ -f "$TMP/app.sha256" ]; then
  EXPECTED="$(awk '{print $1}' "$TMP/app.sha256")"
  ACTUAL="$(sha256_file "$TMP/app.tar.gz")"
  if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "checksum mismatch - refusing to install" >&2
    echo "  expected $EXPECTED" >&2
    echo "  got      $ACTUAL" >&2
    exit 1
  fi
  echo "  checksum ok"
else
  echo "  warning: no checksum published for this build"
fi

if [ "$DRY" = "1" ]; then
  echo "  platform: $OS ($ARCH)"
  echo "  would install into $APP"
  echo "  would register login agent: $([ "$NO_AGENT" = "1" ] && echo no || echo yes)"
  echo "  would start the helper now: yes"
  echo "  the Chrome extension is installed separately: $STORE_URL"
  exit 0
fi

# ---- install ----
HEALTH="http://127.0.0.1:${VICARO_PORT:-8792}/"
up() { curl -fsS -m 2 "$HEALTH" >/dev/null 2>&1; }

if [ "$OS" = "macos" ]; then
  tar -xzf "$TMP/app.tar.gz" -C "$TMP"
  [ -d "$TMP/$APP_NAME.app" ] || { echo "tarball did not contain $APP_NAME.app" >&2; exit 1; }
  # Only this installation's process: a different build elsewhere is not ours to kill.
  # Stop both the tray shell and its helper child; the child keeps port 8792 open and
  # would make the health check below report the old build as "already running".
  pkill -TERM -f "$APP/Contents/MacOS/VicaroHelper" 2>/dev/null || true
  pkill -TERM -f "$APP/Contents/Resources/vicaro-helper" 2>/dev/null || true
  n=0
  while pgrep -f "$APP/Contents/Resources/vicaro-helper" >/dev/null 2>&1 && [ "$n" -lt 10 ]; do
    n=$((n + 1))
    sleep 1
  done

  # Retire the Node app this installer used to ship. Leaving both on disk means a
  # stale login agent can win the next restart and the panel talks to 8790.
  OLD_APP="$DEST/Vicaro Orchestrator.app"
  OLD_AGENT="$HOME/Library/LaunchAgents/com.vicaro.orchestrator.app.plist"
  if [ -d "$OLD_APP" ] || [ -f "$OLD_AGENT" ]; then
    launchctl bootout "gui/$(id -u)/com.vicaro.orchestrator.app" 2>/dev/null || true
    pkill -TERM -f "$OLD_APP/Contents/MacOS/VicaroOrchestrator" 2>/dev/null || true
    rm -rf "$OLD_APP" "$OLD_AGENT"
    echo "  retired: old TypeScript app"
  fi

  mkdir -p "$DEST"
  rm -rf "$APP"
  cp -R "$TMP/$APP_NAME.app" "$APP"
  xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
  echo "  installed: $APP"

  # ---- login agent ----
  AGENT="$HOME/Library/LaunchAgents/com.vicaro.helper.app.plist"
  if [ "$NO_AGENT" = "1" ]; then
    echo "  login agent: skipped"
  else
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$AGENT" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.vicaro.helper.app</string>
  <key>ProgramArguments</key><array>
    <string>$APP/Contents/MacOS/VicaroHelper</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProcessType</key><string>Background</string>
</dict></plist>
PL
    launchctl bootout "gui/$(id -u)/com.vicaro.helper.app" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$AGENT" 2>/dev/null || true
    launchctl kickstart "gui/$(id -u)/com.vicaro.helper.app" 2>/dev/null || true
    echo "  login agent: registered"
  fi

  # ---- start it now ----
  if up; then
    echo "  helper: already running"
  else
    echo "  helper: starting"
    opened=0
    n=0
    while [ "$n" -lt 15 ]; do
      up && break
      if ! pgrep -f "$APP/Contents/MacOS/VicaroHelper" >/dev/null 2>&1; then
        if [ "$opened" = "0" ]; then
          open -a "$APP" 2>/dev/null || true
          opened=1
        fi
      fi
      n=$((n + 1))
      sleep 1
    done
    if up; then
      echo "  helper: running on ${VICARO_PORT:-8792}"
    else
      echo "  helper: started, not answering yet - open Vicaro Helper from Applications"
    fi
  fi
else
  # ---- Linux install ----
  tar -xzf "$TMP/app.tar.gz" -C "$TMP"
  [ -d "$TMP/vicaro-helper" ] || { echo "tarball did not contain vicaro-helper/" >&2; exit 1; }

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user stop vicaro-helper.service 2>/dev/null || true
  fi
  pkill -TERM -f "$APP/vicaro-helper" 2>/dev/null || true
  pkill -TERM -f "$APP/vicaro-helper-ctl tray" 2>/dev/null || true
  n=0
  while pgrep -f "$APP/vicaro-helper" >/dev/null 2>&1 && [ "$n" -lt 10 ]; do
    n=$((n + 1))
    sleep 1
  done

  mkdir -p "$XDG_DATA/vicaro" "$BIN_DIR" "$XDG_DATA/applications" "$XDG_DATA/icons/hicolor/256x256/apps"
  rm -rf "$APP"
  cp -R "$TMP/vicaro-helper" "$APP"
  chmod 0755 "$APP/vicaro-helper" "$APP/vicaro-mcp" "$APP/vicaro-helper-run" "$APP/vicaro-helper-ctl"
  ln -sf "$APP/vicaro-helper-ctl" "$BIN_DIR/vicaro-helper"
  if [ -f "$APP/icons/vicaro.png" ]; then
    cp "$APP/icons/vicaro.png" "$XDG_DATA/icons/hicolor/256x256/apps/vicaro-helper.png"
  fi
  echo "  installed: $APP"
  echo "  cli:       $BIN_DIR/vicaro-helper"

  # Register vicaro:// URL scheme and desktop entry.
  DESKTOP="$XDG_DATA/applications/vicaro-helper.desktop"
  cat > "$DESKTOP" <<DT
[Desktop Entry]
Type=Application
Name=Vicaro Helper
Comment=Self-hosted browser agent helper for Chrome
Exec=$APP/vicaro-helper-ctl open-uri %u
Icon=vicaro-helper
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/vicaro;
Categories=Network;Utility;
DT
  if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default vicaro-helper.desktop x-scheme-handler/vicaro 2>/dev/null || true
  fi
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$XDG_DATA/applications" 2>/dev/null || true
  fi

  # ---- login service + tray autostart ----
  SYSTEMD_OK=0
  SERVICE="$XDG_CONFIG/systemd/user/vicaro-helper.service"
  AUTOSTART="$XDG_CONFIG/autostart/vicaro-helper-tray.desktop"
  if [ "$NO_AGENT" = "1" ]; then
    echo "  login service: skipped"
  else
    mkdir -p "$XDG_CONFIG/systemd/user" "$XDG_CONFIG/autostart"
    cat > "$SERVICE" <<UNIT
[Unit]
Description=Vicaro Helper (local browser agent service)
After=network.target

[Service]
Type=simple
ExecStart=$APP/vicaro-helper-run
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
UNIT

    cat > "$AUTOSTART" <<AUTO
[Desktop Entry]
Type=Application
Name=Vicaro Helper Tray
Comment=Vicaro Helper desktop notifications, account link prompts, and tray menu
Exec=$APP/vicaro-helper-ctl tray
Icon=vicaro-helper
Terminal=false
X-GNOME-Autostart-enabled=true
AUTO

    if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
      systemctl --user daemon-reload 2>/dev/null || true
      if systemctl --user enable --now vicaro-helper.service 2>/dev/null; then
        SYSTEMD_OK=1
        echo "  systemd service: enabled and started"
      fi
    else
      echo "  systemd user session not available - will start helper directly"
    fi
  fi

  # ---- start it now ----
  if up; then
    echo "  helper: already running"
  else
    echo "  helper: starting"
    if [ "$SYSTEMD_OK" = "0" ]; then
      nohup "$APP/vicaro-helper-run" >/dev/null 2>&1 &
    fi
    n=0
    while [ "$n" -lt 15 ]; do
      up && break
      n=$((n + 1))
      sleep 1
    done
    if up; then
      echo "  helper: running on ${VICARO_PORT:-8792}"
    else
      echo "  helper: started, not answering yet - check $XDG_STATE/vicaro/helper.log"
    fi
  fi

  # Launch the desktop tray/notification companion if a graphical session is active.
  if [ "$NO_AGENT" = "0" ] && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
    if command -v python3 >/dev/null 2>&1; then
      nohup "$APP/vicaro-helper-ctl" tray >/dev/null 2>&1 &
    fi
  fi
fi

# ---- AI tools ----
# MCP host registration is part of the helper, but this installer does not write
# other applications' config files. --mcp is accepted so older commands do not
# fail; host setup now lives in the web console either way.
if [ "$WANT_MCP" = "1" ]; then
  echo "  AI tools: open the helper web UI -> Connections -> MCP hosts"
else
  echo "  AI tools: available in the helper web UI -> Connections -> MCP hosts"
fi

echo
echo "Vicaro Helper is installed."
echo
echo "Add Vicaro Beta to Chrome:"
echo "  $STORE_URL"
echo
echo "Open the setup tab or side panel and sign in with Google or an email magic link."
if [ "$OS" = "macos" ]; then
  echo "Data and logs: $HOME/Library/Application Support/Vicaro"
  echo "Uninstall (keeps chats, memories and settings):"
  echo "  launchctl bootout gui/$(id -u)/com.vicaro.helper.app 2>/dev/null;"
  echo "  rm -rf \"$APP\" \"$AGENT\""
else
  echo "Data: $XDG_DATA/vicaro/helper"
  echo "Logs: $XDG_STATE/vicaro/helper.log"
  echo "CLI:  $BIN_DIR/vicaro-helper status"
  echo "Uninstall (keeps chats, memories and settings):"
  echo "  $BIN_DIR/vicaro-helper uninstall"
fi
