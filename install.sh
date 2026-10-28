#!/bin/sh
# Vicaro helper installer (macOS). Reads like a script, because you should read it:
#   curl -fsSL https://vicaro.creativeducks.com/install.sh | sh
#
# What it does, in order: download the app tarball, verify its SHA-256, replace
# ~/Applications/Vicaro Orchestrator.app, register the login agent, then wire Vicaro
# into the AI tools already on this Mac.
#
# The tarball arrives without a quarantine flag (curl does not set one), so macOS
# does not show the "unidentified developer" wall. The app is still ad-hoc signed,
# which is what Apple Silicon requires to run native code.
#
#   --no-agent   do not register the login agent
#   --no-mcp     do not touch any AI tool config
#   --dry-run    print what would happen, change nothing
set -eu

APP_NAME="Vicaro Orchestrator"
# Builds are per-architecture (a universal Node is twice the size); fall back to
# the universal tarball only if no matching arch build was published.
TARBALL="Vicaro-macos-$(uname -m).tar.gz"
# Where the tarball and its .sha256 live. There is no public source repo: publish
# both files to the website (site/downloads/) at release time.
BASE_URL="${VICARO_BASE_URL:-https://vicaro.creativeducks.com/downloads}"

NO_AGENT=0
NO_MCP=0
DRY=0
for arg in "$@"; do
  case "$arg" in
    --no-agent) NO_AGENT=1 ;;
    --no-mcp) NO_MCP=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "unknown option: $arg (use --no-agent, --no-mcp, --dry-run)" >&2; exit 2 ;;
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

echo "Vicaro installer"
echo "  target: $APP"

# ---- fetch ----
if [ -n "${VICARO_TARBALL:-}" ]; then
  cp "$VICARO_TARBALL" "$TMP/app.tar.gz"
  [ -f "$VICARO_TARBALL.sha256" ] && cp "$VICARO_TARBALL.sha256" "$TMP/app.sha256"
else
  echo "  fetching $BASE_URL/$TARBALL"
  if ! curl -fsSL "$BASE_URL/$TARBALL" -o "$TMP/app.tar.gz"; then
    WANTED="$TARBALL"
    TARBALL="Vicaro-macos-universal.tar.gz"
    echo "  no $WANTED for this Mac - trying $TARBALL"
    curl -fsSL "$BASE_URL/$TARBALL" -o "$TMP/app.tar.gz"
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
  echo "  would register login agent: $([ "$NO_AGENT" = "1" ] && echo no || echo yes)"
  echo "  would connect AI tools: $([ "$NO_MCP" = "1" ] && echo no || echo yes)"
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
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>"$APP"</string>
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

# ---- AI tools ----
if [ "$NO_MCP" = "1" ]; then
  echo "  AI tools: skipped"
else
  NODE="$APP/Contents/Resources/node"
  CLI="$APP/Contents/Resources/app/cli/dist/index.js"
  if [ -x "$NODE" ] && [ -f "$CLI" ]; then
    "$NODE" "$CLI" mcp install || echo "  AI tools: skipped (run it later from Settings -> AI tools)"
  else
    echo "  AI tools: this build has no bundled CLI"
  fi
fi

echo
echo "Vicaro is installed."
echo "  1. Open the app in ~/Applications (menu bar icon)."
echo "  2. Allow Local Network access when macOS asks."
echo "  3. Load the extension in Chrome, then open the side panel."
echo
echo "Data and logs: $HOME/Library/Application Support/Vicaro"
echo "Uninstall: launchctl bootout gui/$(id -u)/com.vicaro.orchestrator.app 2>/dev/null;"
echo "           rm -rf \"$APP\" \"$AGENT\" \"$HOME/Library/Application Support/Vicaro\""
