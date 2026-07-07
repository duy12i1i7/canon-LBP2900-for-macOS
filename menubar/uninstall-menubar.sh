#!/bin/bash
#
# Remove the LBP2900 menu-bar progress app.  ./uninstall-menubar.sh
#
set -uo pipefail

LABEL="com.lbp2900.progress"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DEST_DIR="$HOME/Library/Application Support/LBP2900Progress"

echo "==> Stopping and unloading the LaunchAgent"
launchctl unload "$PLIST" 2>/dev/null || true
pkill -f "$DEST_DIR/LBP2900Progress" 2>/dev/null || true

echo "==> Removing files"
rm -f "$PLIST"
rm -rf "$DEST_DIR"

echo "Done. The 🖨 menu-bar icon is removed."
