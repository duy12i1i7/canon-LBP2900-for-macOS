# Canon LBP2900 driver for macOS

**A working driver for the Canon LBP2900 (LASER SHOT / i-SENSYS LBP2900/2900B) on modern macOS — including Apple Silicon — where Canon ships no driver at all.**

🇬🇧 English &nbsp;|&nbsp; [🇻🇳 Tiếng Việt](README.vi.md)

---

The LBP2900 is a **host-based (GDI) printer**: it has no PostScript/PCL interpreter and only speaks Canon's proprietary **CAPT** protocol (Smart Compression Architecture / Hi-SCoA). Canon's official macOS packages only cover the LBP3000 and up, so the 2900 is left unsupported.

This project provides a **CUPS filter** (`rastertocapt`) that implements CAPT, plus a **PPD** describing the printer. It is built on the open-source [captdriver](https://github.com/mounaiban/captdriver) project (GPLv3) with **additional patches required to make the LBP2900 actually print on macOS** (see [The fix](#the-fix)).

> Status: **verified working** — prints real pages on macOS (Apple Silicon, arm64). Page-progress and out-of-paper reporting are integrated into the native macOS print queue.

## What works

- ✅ Printing (600 DPI, all standard paper sizes, plain/heavy/envelope media, toner save, manual duplex)
- ✅ Fully bidirectional CAPT over USB via the standard CUPS `usb` backend — **no kext, no SIP changes**
- ✅ Live **page progress** in the macOS print queue (“Printing page N”)
- ✅ **Out of paper** status + notification; resumes when paper is reloaded
- ✅ Offline / disconnected reporting (handled by the CUPS USB backend)
- ⚠️ Not yet: distinguishing *paper jam* vs *cover open* (the underlying driver doesn’t decode those status bits — see [Roadmap](#roadmap))

## Requirements

- macOS with CUPS (every macOS has it). Tested on macOS 26 (Tahoe-era), Apple Silicon.
- **Apple Silicon (arm64):** a prebuilt filter is bundled — nothing to compile.
- **Intel (x86_64):** no prebuilt binary is bundled; the installer builds from source automatically. You need Xcode Command Line Tools (`xcode-select --install`) and autotools (`brew install autoconf automake`).

## Install — one command

Plug in and power on the printer, then:

```bash
git clone https://github.com/duy12i1i7/canon-LBP2900-for-macOS.git
cd canon-LBP2900-for-macOS
./setup.sh
```

`setup.sh` does everything — run it **without** `sudo` (it asks for your password
only when it needs admin rights):
1. installs the CAPT filter into `/usr/libexec/cups/filter/` (writable data volume; works with SIP enabled) and the PPD into `/Library/Printers/PPDs/…`,
2. detects the USB printer and creates a queue named `Canon_LBP2900`,
3. sets up a **self-healing LaunchDaemon** so the driver survives macOS updates (see below),
4. installs the **menu-bar progress app**.

If the printer isn’t connected yet, everything installs anyway — just re-run
`./setup.sh` once it’s plugged in to add the queue.

<details><summary>Prefer to install the pieces separately?</summary>

```bash
sudo ./install.sh                 # driver + queue + self-heal
cd menubar && ./install-menubar.sh   # menu-bar app (no sudo)
```
</details>

### Surviving macOS updates

A major macOS update can wipe third-party CUPS filters out of `/usr/libexec/cups/filter/`. To make that a non-event, `install.sh` keeps a persistent copy of the filter + PPD in `/Library/Application Support/CanonLBP2900/` (on the data volume, untouched by updates) and installs a LaunchDaemon `com.lbp2900.heal` that runs at every boot and **re-installs the filter/PPD/queue automatically if they went missing**. So after an OS update, the printer just keeps working — no reinstall needed. (Verified by simulating a wipe: the daemon restores the filter on the next run.)

## Usage

Print from any app and pick **Canon LBP2900**, or from the terminal:

```bash
lpr -P Canon_LBP2900 some-file.pdf
lpstat -p Canon_LBP2900        # queue status
```

## Print status monitoring

There is **no Canon-style floating status window** — that’s a closed Windows-only app. Instead, this driver feeds status into the **native macOS print queue window** (System Settings ▸ Printers & Scanners ▸ Canon LBP2900 ▸ *Open Print Queue*, or the Dock icon while printing):

- **Progress** — “Printing page N” (`PAGE:` messages)
- **Out of paper** — a warning badge + notification (`STATE: +media-empty`); reload paper and the job continues
- **Offline / not connected** — reported by the CUPS USB backend when the cable is unplugged or the printer is off

### Multi-page jobs (Word / Excel etc.)

The driver sends pages **one at a time and waits for each to physically print before the next**, and reports progress as it goes. The reliable ways to watch it:

- **Menu-bar app (recommended, no Terminal):** a tiny native app that shows `🖨 2/3` in the menu bar while printing. See [`menubar/`](menubar/) — `cd menubar && ./install-menubar.sh` (no sudo). This exists because Apple's own “Printing N of M” widget is frozen for this printer (see the note below).
- **Terminal (most precise):** run [`progress.sh`](progress.sh):

  ```bash
  ./progress.sh          # prints e.g.  job #12 "Report.xlsx": printed 4/10 pages
  ```

  It reads CUPS’ `job-media-sheets-completed` (driven by the driver’s `PAGE:` reports and verified to advance in real time). From the macOS print dialog the total is usually known, so you get `printed X / Y`; a plain `lpr file.txt` may only show `printed X`.
- **The pages themselves** — one sheet ejects roughly every several seconds.

> **Note on macOS’ “Printing N of M” text — and why the driver can’t fix it.**
> On modern macOS this counter stays frozen at “1 of M” for the LBP2900 (and any
> non-AirPrint / host-based CUPS printer). This was investigated thoroughly and it is
> **not fixable from the driver**, by design:
>
> - The two CUPS job counters the filter *does* drive — `job-media-sheets-completed`
>   and `job-impressions-completed` — were measured advancing correctly live
>   (`0→1→2→3`) as each page prints.
> - Yet the Apple UI ignores them. It even shows the correct total “of 3” while the
>   CUPS `job-impressions` attribute is **unset** — proving Apple’s print proxy reads
>   its page count from the *spool document* on the PrintCore side, not from the CUPS
>   job the driver updates. So there is no filter-side attribute that can move “N”.
> - Live per-page progress in that widget only works for **AirPrint / IPP Everywhere**
>   printers, which report progress back over IPP. The LBP2900 is a raw USB CAPT/GDI
>   device with no IPP, so it structurally can’t feed that widget.
>
> The driver’s progress reporting is correct — use [`progress.sh`](progress.sh) for an
> accurate live count, or just watch the pages. The frozen widget is a macOS platform
> limitation shared by all classic CUPS drivers.

## Troubleshooting

Enable verbose logging and watch it while you print:

```bash
sudo cupsctl LogLevel=debug
tail -f /var/log/cups/error_log      # lines tagged "CAPT:" are from this driver
sudo cupsctl LogLevel=warn           # turn it back off afterwards
```

- **`filter failed`** — check the filter is present and executable:
  `ls -l /usr/libexec/cups/filter/rastertocapt` (should be `-rwxr-xr-x root wheel`). Re-run `sudo ./install.sh` if missing.
- **Job stuck at “now printing” forever (desynced page counters)** — this usually happens after you **cancel a job mid-print**: the cancelled job never sends a clean end-of-job, so the printer’s cumulative page counters drift and the next job waits forever. Fix: `cancel -a Canon_LBP2900`, then **power-cycle the printer** (off ~10 s, on, wait for a steady green light) to reset the counters, and print again. This is a [known captdriver behavior](https://github.com/agalakhov/captdriver/issues/7).
- **macOS auto-adds a “Generic/AirPrint” queue** — the LBP2900 has no AirPrint; use the `Canon_LBP2900` queue created by the installer (it has the correct PPD).
- **Blank or shifted output** — pick the correct paper size (A4/Letter) in the print dialog; the printer needs ~5 mm minimum margins.

## How it works

CUPS filter chain: `app → PDF → cgpdftoraster → rastertocapt → usb backend → printer`.

`rastertocapt` rasterizes each page into CAPT/Hi-SCoA compressed bands and streams them to the printer, using CUPS’ standard **back-channel** (`cupsBackChannelRead`) and **side-channel** (`cupsSideChannelDoRequest`) APIs for the bidirectional status handshake. That’s why it needs no kernel extension and no elevated privileges beyond `sudo` at install time.

### The fix

Upstream captdriver registers the LBP2900 with a *conditional* status strategy (`capt_get_xstatus` / `capt_wait_ready`). That only fetches the **extended** printer status (CAPT command `0xA0A8`) when the `XSTATUS_CHNG` flag is set — which this unit never sets. The per-page counters (`page_decoding` / `page_out` / `page_completed`) live **only** in the extended status record, so they were never refreshed, leaving stale/garbage values and hanging the end-of-page wait loops (the classic endlessly-looping `0xE0A0` status poll, [captdriver#3](https://github.com/mounaiban/captdriver/issues/3)).

The patch switches the LBP2900 to the same strategy the known-working LBP3010 uses — **always** read the extended status (`capt_get_xstatus_only` / `capt_wait_xready_only`). Once the counters are read correctly they converge (`1/1/1/1`) and the page prints. The same patch also adds the `PAGE:`/`STATE:` reporting described above. See [`patches/lbp2900-macos.patch`](patches/lbp2900-macos.patch).

This behaviour matches the reverse-engineered CAPT protocol spec (see [`captdriver/SPECS`](captdriver/SPECS)): the extended-status record (reply to `0xA0A8`) carries the page counters at bytes 14–21, and paper-out is STATUS0 bit 1 / STATUS1 bit 14.

## Build from source

Prebuilt arm64 filter is under `prebuilt/arm64/`. To rebuild (e.g. for Intel or a universal binary), see [`docs/BUILD.md`](docs/BUILD.md). In short:

```bash
cd captdriver
autoreconf -fi && ./configure
make CFLAGS="-D_DARWIN_C_SOURCE -std=gnu99 -O2"     # -> src/rastertocapt
```

The `captdriver/` tree here is upstream captdriver **with the macOS/LBP2900 patch already applied**, included both for one-command building and for GPLv3 source-availability compliance.

## Roadmap

- Decode the cover-open / paper-jam status bits (STATUS2 bit 7 = “Problem” per the spec) to show distinct errors instead of a generic stall.
- Universal (arm64 + x86_64) prebuilt binary.

## Credits

- [captdriver](https://github.com/mounaiban/captdriver) by Moses Chong and contributors — the CAPT CUPS filter this is built on.
- The original CAPT reverse engineering by **Alexey Galakhov**, Nicolas Boichat, Benoit Bolsee and others (see [`captdriver/AUTHORS`](captdriver/AUTHORS) and [`captdriver/SPECS`](captdriver/SPECS)).
- macOS port, LBP2900 status-strategy fix, and native status reporting: this repository.

This is unofficial software, not endorsed by or affiliated with Canon Inc.

## License

**GNU General Public License v3** — see [`LICENSE`](LICENSE). captdriver is GPLv3, and this derivative work (patches + built binary) is distributed under the same terms.
