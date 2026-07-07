# LBP2900 menu-bar progress

A tiny native macOS menu-bar app that shows **live print progress** for the
Canon LBP2900 — e.g. `🖨 2/3` while printing, `🖨` when idle.

## Why

Apple's own “Printing N of M” widget is **frozen at “1”** for the LBP2900 (and any
non-AirPrint / host-based CUPS printer): that widget asks the *printer* for the
current page over IPP, and a raw USB CAPT device can't answer. The CUPS job counter
the driver updates (`job-media-sheets-completed`) **is** correct, so this app reads
that and shows it in the menu bar instead — no Terminal, no external window.

## Install

```bash
cd menubar
./install-menubar.sh      # no sudo needed
```

This installs the app to `~/Library/Application Support/LBP2900Progress/`, adds a
LaunchAgent so it starts at login (and restarts if it quits), and launches it now.
Look for the **🖨** icon at the top-right of the menu bar.

- While printing: `🖨 2/3` (current page / total). If the total isn't known
  (e.g. some command-line jobs) it shows just `🖨 2`.
- Idle: `🖨`. Click it for status and a **Quit** option.

## Uninstall

```bash
./uninstall-menubar.sh
```

## Build from source

Needs Xcode Command Line Tools (`xcode-select --install`). The installer builds
automatically if the binary is missing, or:

```bash
swiftc -O LBP2900Progress.swift -o LBP2900Progress
```

Prebuilt binary is **arm64** (Apple Silicon). On Intel, the installer rebuilds it.

## Notes

- Runs as an *accessory* app (menu-bar only, no Dock icon).
- Polls the print queue every 1.5 s via `ipptool`.
- The queue name is `Canon_LBP2900` (matches the driver's `install.sh`). If you
  named your queue differently, edit `QUEUE` at the top of `LBP2900Progress.swift`
  and rebuild.
