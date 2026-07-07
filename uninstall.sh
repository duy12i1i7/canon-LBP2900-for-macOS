#!/bin/bash
#
# Remove the Canon LBP2900 driver.  sudo ./uninstall.sh
#
set -uo pipefail

QUEUE="Canon_LBP2900"
FILTER_DST="/usr/libexec/cups/filter/rastertocapt"
PPD_DST="/Library/Printers/PPDs/Contents/Resources/CanonLBP-2900-3000.ppd"
STASH="/Library/Application Support/CanonLBP2900"
DAEMON_PLIST="/Library/LaunchDaemons/com.lbp2900.heal.plist"

if [ "$(id -u)" -ne 0 ]; then
  echo "!! Please run as administrator:  sudo ./uninstall.sh" >&2
  exit 1
fi

echo "==> Removing self-heal daemon"
launchctl unload "$DAEMON_PLIST" 2>/dev/null || true
rm -f "$DAEMON_PLIST"
rm -rf "$STASH"

echo "==> Removing print queue $QUEUE"
/usr/sbin/lpadmin -x "$QUEUE" 2>/dev/null || echo "   (no queue $QUEUE, skipping)"

echo "==> Removing filter $FILTER_DST"
rm -f "$FILTER_DST"

echo "==> Removing PPD $PPD_DST"
rm -f "$PPD_DST"

echo "Done. Canon LBP2900 driver removed."
