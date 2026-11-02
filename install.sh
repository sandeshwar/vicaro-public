#!/bin/sh
# Vicaro helper installer (macOS). Reads like a script, because you should read it:
#   curl -fsSL https://vicaro.creativeducks.com/install.sh | sh
#
# What it does, in order: download the app tarball, verify its SHA-256, replace
# ~/Applications/Vicaro Orchestrator.app, stage the Chrome extension, register the
# login agent. It leaves other apps alone: connecting Cursor, Claude Code or Codex
# is opt-in (--mcp), and the same switch is in Settings -> AI tools.
#
# The tarball arrives without a quarantine flag (curl does not set one), so macOS
# does not show the "unidentified developer" wall. The app is still ad-hoc signed,
# which is what Apple Silicon requires to run native code.
#
#   --no-agent       do not register the login agent
#   --no-extension   do not stage the Chrome extension
#   --mcp            also connect the AI tools already on this Mac
#   --no-open        do not launch Chrome or Finder at the end
#   --dry-run        print what would happen, change nothing
set -eu

APP_NAME="Vicaro Orchestrator"
# Builds are per-architecture (a universal Node is twice the size); fall back to
# the universal tarball only if no matching arch build was published.
TARBALL="Vicaro-macos-$(uname -m).tar.gz"
# Where the tarball and its .sha256 live. GitHub Releases is the primary: free,
# CDN-backed, and it keeps install traffic away from the site's bandwidth.
# FALLBACK_URL is the old /downloads path, used only if the release is missing.
BASE_URL="${VICARO_BASE_URL:-https://github.com/sandeshwar/vicaro-public/releases/latest/download}"
FALLBACK_URL="https://vicaro.creativeducks.com/downloads"

NO_AGENT=0
WANT_MCP=0
NO_EXT=0
NO_OPEN=0
DRY=0
for arg in "$@"; do
  case "$arg" in
    --no-agent) NO_AGENT=1 ;;
    --mcp) WANT_MCP=1 ;;
    --no-mcp) WANT_MCP=0 ;;
    --no-extension) NO_EXT=1 ;;
    --no-open) NO_OPEN=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "unknown option: $arg (use --no-agent, --no-extension, --mcp, --no-open, --dry-run)" >&2; exit 2 ;;
  esac
done

case "$(uname -m)" in
  arm64|x86_64) ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
if [ "$(uname -s)" != "Darwin" ]; then
  echo "this installer is macOS only - on Linux use the .deb or AppImage" >&2; exit 1
fi

DEST="$HOME/Applications"
APP="$DEST/$APP_NAME.app"
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
    WANTED="$TARBALL"
    TARBALL="Vicaro-macos-universal.tar.gz"
    echo "  no $WANTED for this Mac - trying $TARBALL"
    if ! fetch "$BASE_URL/$TARBALL" "$TMP/app.tar.gz" "$TARBALL"; then
      # Releases moved, were unpublished, or the network blocks github.com.
      echo "  no release asset - falling back to $FALLBACK_URL"
      BASE_URL="$FALLBACK_URL"
      fetch "$BASE_URL/$TARBALL" "$TMP/app.tar.gz" "$TARBALL"
    fi
  fi
  curl -fsSL "$BASE_URL/$TARBALL.sha256" -o "$TMP/app.sha256"
fi

# ---- verify ----
if [ -f "$TMP/app.sha256" ]; then
  EXPECTED="$(cut -d' ' -f1 "$TMP/app.sha256")"
  ACTUAL="$(shasum -a 256 "$TMP/app.tar.gz" | cut -d' ' -f1)"
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
  echo "  would install into $APP"
  echo "  would stage the Chrome extension: $([ "$NO_EXT" = "1" ] && echo no || echo yes)"
  echo "  would register login agent: $([ "$NO_AGENT" = "1" ] && echo no || echo yes)"
  echo "  would start the helper now: yes"
  echo "  would connect AI tools: $([ "$WANT_MCP" = "1" ] && echo yes || echo "no (Settings -> AI tools)")"
  exit 0
fi

# ---- install ----
tar -xzf "$TMP/app.tar.gz" -C "$TMP"
[ -d "$TMP/$APP_NAME.app" ] || { echo "tarball did not contain $APP_NAME.app" >&2; exit 1; }
# Only this installation's process: a different build elsewhere is not ours to kill.
pkill -TERM -f "$APP/Contents/MacOS/VicaroOrchestrator" 2>/dev/null || true
mkdir -p "$DEST"
rm -rf "$APP"
cp -R "$TMP/$APP_NAME.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
echo "  installed: $APP"

# ---- Chrome extension ----
# Chrome has no way to install an unpacked extension from a script, and it never
# will. So stage it in a stable folder, put the path on the clipboard, and open the
# extensions page: the user's part is three clicks.
EXT_DIR="$HOME/Library/Application Support/Vicaro/extension"
EXT_OK=0
if [ "$NO_EXT" = "1" ]; then
  echo "  extension: skipped"
else
  mkdir -p "$HOME/Library/Application Support/Vicaro"
  if curl -fsSL "$BASE_URL/Vicaro-extension.zip" -o "$TMP/ext.zip" 2>/dev/null; then
    rm -rf "$TMP/ext" && mkdir -p "$TMP/ext"
    if unzip -q "$TMP/ext.zip" -d "$TMP/ext" 2>/dev/null && [ -f "$TMP/ext/manifest.json" ]; then
      # Swap the directory rather than unpacking over it: Chrome may be reading it.
      rm -rf "$EXT_DIR"
      cp -R "$TMP/ext" "$EXT_DIR"
      EXT_OK=1
      echo "  extension: staged at $EXT_DIR"
    else
      echo "  extension: download was not a valid package - skipping"
    fi
  else
    echo "  extension: not published for this release - skipping"
  fi
fi

# ---- login agent ----
AGENT="$HOME/Library/LaunchAgents/com.vicaro.orchestrator.app.plist"
if [ "$NO_AGENT" = "1" ]; then
  echo "  login agent: skipped"
else
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$AGENT" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.vicaro.orchestrator.app</string>
  <key>ProgramArguments</key><array>
    <string>"$APP/Contents/MacOS/VicaroOrchestrator"</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProcessType</key><string>Background</string>
</dict></plist>
PL
  launchctl bootout "gui/$(id -u)/com.vicaro.orchestrator.app" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$AGENT" 2>/dev/null || true
  launchctl kickstart "gui/$(id -u)/com.vicaro.orchestrator.app" 2>/dev/null || true
  echo "  login agent: registered"
fi

# ---- start it now ----
# The agent covers future logins; installing should also leave a helper that is
# already answering, otherwise the first thing the panel shows is "connecting".
# Both launchctl calls above are best-effort (they fail outside a GUI session), so
# this is what actually guarantees the app is up, and it reports the truth.
HEALTH="http://127.0.0.1:${VICARO_PORT:-8790}/health"
up() { curl -fsS -m 2 "$HEALTH" >/dev/null 2>&1; }
if up; then
  echo "  helper: already running"
else
  echo "  helper: starting"
  # Never start a second copy: the login agent may have launched it a moment ago,
  # and two instances race for the port and leave nothing running.
  opened=0
  n=0
  while [ "$n" -lt 15 ]; do
    up && break
    if ! pgrep -f "$APP/Contents/MacOS/VicaroOrchestrator" >/dev/null 2>&1; then
      if [ "$opened" = "0" ]; then
        open -a "$APP" 2>/dev/null || true
        opened=1
      fi
    fi
    n=$((n + 1))
    sleep 1
  done
  if up; then
    echo "  helper: running on ${VICARO_PORT:-8790}"
  else
    echo "  helper: started, not answering yet - open Vicaro Orchestrator from Applications"
  fi
fi

# ---- AI tools (opt-in) ----
# Not by default: installing a helper should not rewrite another app's config files
# unasked. Settings -> AI tools does exactly this later, with a checkbox per tool.
if [ "$WANT_MCP" = "1" ]; then
  NODE="$APP/Contents/Resources/node"
  CLI="$APP/Contents/Resources/app/cli/dist/index.js"
  if [ -x "$NODE" ] && [ -f "$CLI" ]; then
    "$NODE" "$CLI" mcp install || echo "  AI tools: skipped (run it later from Settings -> AI tools)"
  else
    echo "  AI tools: this build has no bundled CLI"
  fi
else
  echo "  AI tools: not connected (Settings -> AI tools, or rerun with --mcp)"
fi

echo
echo "Vicaro is installed. Two things left, both in Chrome."

if [ "$EXT_OK" = "1" ]; then
  printf '%s' "$EXT_DIR" | pbcopy 2>/dev/null || true
  if [ "$NO_OPEN" != "1" ]; then
    open -a "Google Chrome" "chrome://extensions/" 2>/dev/null || open -R "$EXT_DIR/manifest.json" 2>/dev/null || true
  fi
  echo
  if [ "$NO_OPEN" = "1" ]; then
    echo "  Add the extension:"
  else
    echo "  Add the extension (Chrome is opening for you):"
  fi
  echo "    1. Turn on Developer mode, top right."
  echo "    2. Click Load unpacked."
  echo "    3. Press Cmd+Shift+G, paste, Return - the folder is on your clipboard."
  echo "       $EXT_DIR"
  echo "    4. Pin Vicaro in the toolbar and click it to open the side panel."
else
  echo
  echo "  Add the extension: download Vicaro-extension.zip, unzip it, then"
  echo "  chrome://extensions -> Developer mode -> Load unpacked."
fi

echo
echo "  Then open the panel, point it at a model, and allow Local Network access when asked."
echo "  Vicaro needs a model: one running on this Mac, or any OpenAI-compatible endpoint."
echo "Data and logs: $HOME/Library/Application Support/Vicaro"
echo "Uninstall: launchctl bootout gui/$(id -u)/com.vicaro.orchestrator.app 2>/dev/null;"
echo "           rm -rf \"$APP\" \"$AGENT\" \"$HOME/Library/Application Support/Vicaro\""
