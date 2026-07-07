#!/bin/bash
#
# Install the LBP2900 menu-bar progress app and start it at login.
# User-level only — no sudo needed.
#
#   ./install-menubar.sh
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="LBP2900Progress"
DEST_DIR="$HOME/Library/Application Support/LBP2900Progress"
DEST_BIN="$DEST_DIR/$APP_NAME"
LABEL="com.lbp2900.progress"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# 1. Get a binary (use the prebuilt one, or build it).
SRC_BIN="$DIR/$APP_NAME"
if [ ! -x "$SRC_BIN" ]; then
  echo "==> Building $APP_NAME from source"
  if ! command -v swiftc >/dev/null 2>&1; then
    echo "!! swiftc not found. Install Xcode Command Line Tools: xcode-select --install" >&2
    exit 1
  fi
  ( cd "$DIR" && swiftc -O "$APP_NAME.swift" -o "$APP_NAME" )
  SRC_BIN="$DIR/$APP_NAME"
fi

# 2. Install the binary.
echo "==> Installing app -> $DEST_BIN"
mkdir -p "$DEST_DIR"
cp "$SRC_BIN" "$DEST_BIN"
chmod 755 "$DEST_BIN"
# Clear the quarantine flag in case the repo was downloaded as a zip.
xattr -d com.apple.quarantine "$DEST_BIN" 2>/dev/null || true

# 3. Write the LaunchAgent so it starts at login and restarts if it dies.
echo "==> Installing LaunchAgent -> $PLIST"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>$LABEL</string>
    <key>ProgramArguments</key> <array><string>$DEST_BIN</string></array>
    <key>RunAtLoad</key>        <true/>
    <key>KeepAlive</key>        <true/>
    <key>ProcessType</key>      <string>Interactive</string>
</dict>
</plist>
PLISTEOF

# 4. (Re)load it. RunAtLoad=true starts it immediately (no re-login needed);
#    KeepAlive=true restarts it if it ever quits. launchd owns the single
#    instance — don't launch a second copy by hand.
pkill -f "$DEST_BIN" 2>/dev/null || true
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo
echo "OK. Look for the 🖨 icon in the menu bar (top-right)."
echo "It shows e.g. '🖨 2/3' while printing, and '🖨' when idle."
echo "Uninstall with: ./uninstall-menubar.sh"
