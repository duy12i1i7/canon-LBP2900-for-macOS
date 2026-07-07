#!/bin/bash
#
# Canon LBP2900 for macOS — all-in-one setup.
#
#   ./setup.sh
#
# Installs everything in one go:
#   1. the CAPT print driver (filter + PPD) and the print queue,
#   2. a self-healing daemon that survives macOS updates,
#   3. the menu-bar progress app.
#
# Run it WITHOUT sudo — it asks for your password only for the driver step.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -eq 0 ]; then
  echo "!! Run WITHOUT sudo:  ./setup.sh" >&2
  echo "   (it will ask for your password when it needs admin rights)" >&2
  exit 1
fi

echo "════════════════════════════════════════════════════════"
echo "  Canon LBP2900 for macOS — all-in-one setup"
echo "════════════════════════════════════════════════════════"

# If this repo was downloaded as a .zip, macOS quarantines the binaries.
# Clear it so the filter and menu-bar app can run.
xattr -dr com.apple.quarantine "$DIR" 2>/dev/null || true

# Friendly heads-up if the printer isn't plugged in.
if ! /usr/sbin/lpinfo -v 2>/dev/null | grep -qiE 'usb:.*(canon|lbp29)'; then
  echo
  echo "Note: the LBP2900 doesn't seem to be connected. Plug it in and power it on"
  echo "for the print queue to be created now. (Everything else installs anyway;"
  echo "re-run ./setup.sh later to add the queue.)"
  echo
fi

echo "==> Step 1/2 — driver, queue and self-heal (needs admin)"
sudo bash "$DIR/install.sh"

echo
echo "==> Step 2/2 — menu-bar progress app"
bash "$DIR/menubar/install-menubar.sh"

echo
echo "════════════════════════════════════════════════════════"
echo "  ✅ Done. Print from any app and choose 'Canon LBP2900'."
echo "  • Progress shows as 🖨 N/M in the menu bar while printing."
echo "  • The driver auto-reinstalls itself after macOS updates."
echo "  • Uninstall: sudo ./uninstall.sh  and  menubar/uninstall-menubar.sh"
echo "════════════════════════════════════════════════════════"
