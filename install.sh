#!/bin/bash
#
# Canon LBP2900 driver installer for macOS.
#   sudo ./install.sh
#
# Installs the CAPT CUPS filter + PPD and creates a print queue for a
# USB-connected Canon LBP2900. Uses the prebuilt filter for your CPU
# architecture, or builds it from source (captdriver/) if none is bundled.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PPD_SRC="$DIR/ppd/CanonLBP-2900-3000.ppd"
FILTER_DST="/usr/libexec/cups/filter/rastertocapt"
PPD_DST_DIR="/Library/Printers/PPDs/Contents/Resources"
PPD_NAME="CanonLBP-2900-3000.ppd"
PPD_DST="$PPD_DST_DIR/$PPD_NAME"

QUEUE="Canon_LBP2900"
DESC="Canon LBP2900"

LPINFO=/usr/sbin/lpinfo
LPADMIN=/usr/sbin/lpadmin
CUPSENABLE=/usr/sbin/cupsenable
CUPSACCEPT=/usr/sbin/cupsaccept

if [ "$(id -u)" -ne 0 ]; then
  echo "!! Please run as administrator:  sudo ./install.sh" >&2
  exit 1
fi

# --- Pick or build the filter binary ---------------------------------------
ARCH="$(uname -m)"
FILTER_SRC="$DIR/prebuilt/$ARCH/rastertocapt"

if [ ! -f "$FILTER_SRC" ]; then
  echo "==> No prebuilt filter for '$ARCH' — building from source (captdriver/)"
  if ! command -v cups-config >/dev/null 2>&1; then
    echo "!! cups-config not found. Install Xcode Command Line Tools:" >&2
    echo "   xcode-select --install" >&2
    exit 1
  fi
  ( cd "$DIR/captdriver"
    if [ ! -x configure ]; then autoreconf -fi; fi
    ./configure >/dev/null
    make CFLAGS="-D_DARWIN_C_SOURCE -std=gnu99 -O2" )
  FILTER_SRC="$DIR/captdriver/src/rastertocapt"
  if [ ! -f "$FILTER_SRC" ]; then
    echo "!! Build failed — see messages above." >&2
    exit 1
  fi
fi

echo "==> 1/4  Installing filter  -> $FILTER_DST"
install -o root -g wheel -m 0755 "$FILTER_SRC" "$FILTER_DST"

echo "==> 2/4  Installing PPD     -> $PPD_DST"
mkdir -p "$PPD_DST_DIR"
install -o root -g wheel -m 0644 "$PPD_SRC" "$PPD_DST"

echo "==> 3/4  Looking for the USB printer..."
URI="$("$LPINFO" -v 2>/dev/null | awk '$2 ~ /^usb:/ && (tolower($2) ~ /canon/ || $2 ~ /LBP29?00/){print $2; exit}')"
if [ -z "${URI:-}" ]; then
  URI="$("$LPINFO" -v 2>/dev/null | awk '$2 ~ /^usb:/{print $2; exit}')"
fi

if [ -z "${URI:-}" ]; then
  echo
  echo "   No USB printer detected."
  echo "   -> Plug in and power on the LBP2900, then re-run:  sudo ./install.sh"
  echo "   The filter and PPD are already installed, so the next run only needs"
  echo "   to add the print queue."
  exit 0
fi

echo "    Found: $URI"
echo "==> 4/4  Creating print queue '$QUEUE'"
"$LPADMIN" -p "$QUEUE" -v "$URI" -P "$PPD_DST" -E -D "$DESC" -o printer-is-shared=false
"$CUPSENABLE" "$QUEUE" 2>/dev/null || true
"$CUPSACCEPT" "$QUEUE" 2>/dev/null || true

echo
echo "OK. Printer '$DESC' is ready (queue: $QUEUE)."
echo "   Test:    lpr -P $QUEUE some-file.pdf"
echo "   Status:  lpstat -p $QUEUE"
