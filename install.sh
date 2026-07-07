#!/bin/bash
#
# Canon LBP2900 driver installer for macOS.
#   sudo ./install.sh
#
# Installs the CAPT CUPS filter + PPD, creates a print queue for a USB-connected
# Canon LBP2900, and sets up a self-healing LaunchDaemon so a macOS update that
# wipes the filter re-installs it automatically at the next boot.
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

# Persistent stash + self-heal daemon (both on the data volume -> survive OS updates)
STASH="/Library/Application Support/CanonLBP2900"
HEAL="$STASH/heal.sh"
DAEMON_LABEL="com.lbp2900.heal"
DAEMON_PLIST="/Library/LaunchDaemons/$DAEMON_LABEL.plist"

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

echo "==> 1/5  Installing filter  -> $FILTER_DST"
install -o root -g wheel -m 0755 "$FILTER_SRC" "$FILTER_DST"

echo "==> 2/5  Installing PPD     -> $PPD_DST"
mkdir -p "$PPD_DST_DIR"
install -o root -g wheel -m 0644 "$PPD_SRC" "$PPD_DST"

# --- Set up the self-healing stash + daemon (idempotent) -------------------
setup_selfheal() {
  local uri="${1:-}"
  echo "==> Setting up self-heal (survives macOS updates) -> $STASH"
  mkdir -p "$STASH"
  install -o root -g wheel -m 0755 "$FILTER_SRC" "$STASH/rastertocapt"
  install -o root -g wheel -m 0644 "$PPD_SRC"    "$STASH/CanonLBP-2900-3000.ppd"
  [ -n "$uri" ] && printf '%s\n' "$uri" > "$STASH/device-uri"

  cat > "$HEAL" <<'HEALEOF'
#!/bin/bash
# Auto-restore the Canon LBP2900 CUPS filter/PPD/queue if a macOS update removed
# them. Run at boot by com.lbp2900.heal. Everything here is idempotent.
STASH="/Library/Application Support/CanonLBP2900"
FILTER="/usr/libexec/cups/filter/rastertocapt"
PPDDIR="/Library/Printers/PPDs/Contents/Resources"
PPD="$PPDDIR/CanonLBP-2900-3000.ppd"
QUEUE="Canon_LBP2900"

if [ ! -x "$FILTER" ] && [ -f "$STASH/rastertocapt" ]; then
  /usr/bin/install -o root -g wheel -m 0755 "$STASH/rastertocapt" "$FILTER" \
    && /usr/bin/logger -t lbp2900-heal "restored filter"
fi
if [ ! -f "$PPD" ] && [ -f "$STASH/CanonLBP-2900-3000.ppd" ]; then
  /bin/mkdir -p "$PPDDIR"
  /usr/bin/install -o root -g wheel -m 0644 "$STASH/CanonLBP-2900-3000.ppd" "$PPD" \
    && /usr/bin/logger -t lbp2900-heal "restored PPD"
fi
# Re-add the queue only if it vanished. Prefer a live-detected URI, else the stored one.
if ! /usr/bin/lpstat -p "$QUEUE" >/dev/null 2>&1; then
  URI="$(/usr/sbin/lpinfo -v 2>/dev/null | /usr/bin/awk '$2 ~ /^usb:/ && (tolower($2) ~ /canon/ || $2 ~ /LBP29?00/){print $2; exit}')"
  [ -z "$URI" ] && URI="$(/bin/cat "$STASH/device-uri" 2>/dev/null)"
  if [ -n "$URI" ] && [ -f "$PPD" ]; then
    /usr/sbin/lpadmin -p "$QUEUE" -v "$URI" -P "$PPD" -E -D "Canon LBP2900" \
      -o printer-is-shared=false -o printer-error-policy=stop-printer \
      && /usr/bin/logger -t lbp2900-heal "restored queue"
  fi
fi
exit 0
HEALEOF
  chmod 0755 "$HEAL"

  cat > "$DAEMON_PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>$DAEMON_LABEL</string>
    <key>ProgramArguments</key> <array><string>/bin/bash</string><string>$HEAL</string></array>
    <key>RunAtLoad</key>        <true/>
    <key>StandardErrorPath</key><string>/var/log/lbp2900-heal.log</string>
</dict>
</plist>
PLISTEOF
  chown root:wheel "$DAEMON_PLIST"; chmod 0644 "$DAEMON_PLIST"
  launchctl unload "$DAEMON_PLIST" 2>/dev/null || true
  launchctl load "$DAEMON_PLIST" 2>/dev/null || true
}

echo "==> 3/5  Looking for the USB printer..."
URI="$("$LPINFO" -v 2>/dev/null | awk '$2 ~ /^usb:/ && (tolower($2) ~ /canon/ || $2 ~ /LBP29?00/){print $2; exit}')"
if [ -z "${URI:-}" ]; then
  URI="$("$LPINFO" -v 2>/dev/null | awk '$2 ~ /^usb:/{print $2; exit}')"
fi

if [ -z "${URI:-}" ]; then
  echo "==> 4/5  (no printer yet — skipping queue creation)"
  echo "==> 5/5"; setup_selfheal ""
  echo
  echo "   Filter, PPD and self-heal are installed."
  echo "   -> Plug in and power on the LBP2900, then re-run:  sudo ./install.sh"
  exit 0
fi

echo "    Found: $URI"
echo "==> 4/5  Creating print queue '$QUEUE'"
"$LPADMIN" -p "$QUEUE" -v "$URI" -P "$PPD_DST" -E -D "$DESC" \
  -o printer-is-shared=false -o printer-error-policy=stop-printer
"$CUPSENABLE" "$QUEUE" 2>/dev/null || true
"$CUPSACCEPT" "$QUEUE" 2>/dev/null || true

echo "==> 5/5"; setup_selfheal "$URI"

echo
echo "OK. Printer '$DESC' is ready (queue: $QUEUE)."
echo "   It will auto-reinstall itself after macOS updates."
echo "   Status:  lpstat -p $QUEUE"
