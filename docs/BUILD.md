# Building `rastertocapt` from source

The `captdriver/` directory in this repo is upstream
[captdriver](https://github.com/mounaiban/captdriver) with the macOS/LBP2900
patch (`patches/lbp2900-macos.patch`) already applied. You only need to build if
there is no prebuilt binary for your CPU (e.g. Intel), or if you change the code.

## Requirements

- Xcode Command Line Tools: `xcode-select --install`
- autotools: `brew install autoconf automake`
- CUPS headers ship with macOS (no extra install needed).

## Build

```bash
cd captdriver
autoreconf -fi
./configure

# IMPORTANT: define _DARWIN_C_SOURCE, otherwise the strict -std=c99 -pedantic
# flags hide the BSD types (u_char/u_int) that macOS network headers pulled in
# via <cups/http.h> require, and the build fails with "unknown type name u_char".
make CFLAGS="-D_DARWIN_C_SOURCE -std=gnu99 -O2"
# result: captdriver/src/rastertocapt
```

Copy the result over the bundled prebuilt binary if you want `install.sh` to use
it, or just run `sudo ../install.sh` — the installer auto-builds when no prebuilt
binary matches your architecture.

## Universal (arm64 + x86_64) binary

Build once per arch, then combine:

```bash
# on/for each arch, produce src/rastertocapt, then:
lipo -create rastertocapt.arm64 rastertocapt.x86_64 -output rastertocapt
```

## Regenerating the PPD

The PPD is generated from `captdriver/src/canon-lbp.drv` with the CUPS compiler:

```bash
ppdc -d out captdriver/src/canon-lbp.drv
# -> out/CanonLBP-2900-3000.ppd
```

## The patch

All macOS/LBP2900 changes live in `patches/lbp2900-macos.patch`. To apply it to a
fresh upstream checkout:

```bash
git clone https://github.com/mounaiban/captdriver.git
cd captdriver
patch -p1 < /path/to/patches/lbp2900-macos.patch
```

It contains six changes:

1. **Hang fix** — register the LBP2900 with the LBP3010 ("WORKS") status
   strategy (`capt_get_xstatus_only` / `capt_wait_xready_only`) so the per-page
   counters, which only exist in the extended status reply (`0xA0A8`), are always
   refreshed. Without this the end-of-page wait loops never terminate.
2. **`PAGE:`** progress reporting in `rastertocapt.c` (drives `job-media-sheets-completed`).
3. **`STATE: +/-media-empty`** in `prn_lbp2900.c` → macOS shows "Out of paper".
4. **Faster polling** — the stock driver polled printer status once per second
   (`sleep(1)`) in every wait loop, idling the engine up to ~1 s per handshake and
   stalling multi-page jobs between sheets. Poll every 100 ms (`CAPT_POLL_US` in
   `std.h`) and check-before-wait, so multi-page jobs print near-continuously.
   Measured: inter-page gap dropped from ~9–11 s to ~6–7 s per page (engine
   native is ~5 s).
5. **Bounded wait timeouts** — every status-wait loop is capped
   (`CAPT_WAIT_POLLS_PAGE`/`_JOB` in `prn_lbp2900.c`, ~20–25 s). With fix #1 these
   are essentially never hit, but they guarantee a freak page whose status never
   settles can't hang the queue forever (a safety net inspired by the
   bechou0410/canon-lbp2900-macos27-driver project, without its per-page slowdown).
6. **Blink the printer LED on out-of-paper** — send the GPIO blink command when
   `NOPAPER` is detected so it's obvious at the machine, not just in the queue.

## Quick self-test (no printer needed)

Round-trips the Hi-SCoA compressor (the most endianness-sensitive part):

```bash
cd captdriver/tests
cc -D_DARWIN_C_SOURCE -std=gnu99 -O2 -I../src -o /tmp/test-hiscoa \
   test-hiscoa.c hiscoa-decompress.c ../src/hiscoa-compress.c ../src/hiscoa-common.c
printf 'P4\ntag\n800 210\n' > /tmp/t.pbm && head -c 21000 /dev/zero >> /tmp/t.pbm
/tmp/test-hiscoa < /tmp/t.pbm 2>&1 | grep FINISHED     # expect: FINISHED - 0 errors
```
