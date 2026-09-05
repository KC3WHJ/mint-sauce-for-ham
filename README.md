# mint-sauce-for-ham

One script to set up a full ham radio + SDR station on Linux Mint (or any
Ubuntu-based distro): ADS-B aircraft tracking, general-purpose SDR
reception, and a Wine-based digital-modes stack for the Icom IC-705.

## What it installs

- **RTL-SDR + readsb + tar1090** — ADS-B aircraft tracking with a live map
  at `http://localhost/tar1090/`. Includes a DVB-T kernel driver blacklist
  (the RTL2838 dongle otherwise gets claimed by the wrong driver) and gpsd
  configured to auto-detect any USB GPS receiver for live station position.
- **The official ADS-B Exchange feed client** — feeds your ADS-B data to
  [adsbexchange.com](https://www.adsbexchange.com). Interactive: it asks
  for your station's lat/lon/altitude and, optionally, your own account
  UUID.
- **SDR++** — general-purpose SDR receiver software, with two helper
  scripts/shortcuts to flip the RTL-SDR dongle between its two mutually
  exclusive modes:
  - *Airband/VHF/UHF* — normal tuner mode: aircraft AM, 6m/2m/70cm ham bands.
  - *HF/Shortwave* — direct-sampling mode for ham HF bands and shortwave
    broadcast. This bypasses the tuner entirely, so airband/VHF/UHF won't
    work while it's active.
- **VarAC, VARA HF, VARA FM** (under Wine), **Pat Winlink**, **JS8Call**,
  **WSJT-X**, and **GridTracker** — all sharing the IC-705 via a single
  Hamlib `rigctld` instance talking directly to its USB CI-V port.

## Prerequisites

- A Debian/Ubuntu-based distro (built and tested on Linux Mint).
- An RTL-SDR dongle (any RTL2832U-based one) if you want the ADS-B/SDR++
  pieces.
- An Icom IC-705 if you want the ham digital-modes stack.
- The proprietary/Windows installers for VarAC, VARA HF, VARA FM, plus the
  JS8Call/WSJT-X/GridTracker/Pat `.deb` packages, downloaded ahead of time
  into `~/Downloads` (or wherever `DOWNLOADS` points to in your config).
  None of these are freely redistributable, so the script doesn't fetch
  them for you — everything else (rtl-sdr, readsb, tar1090, gpsd, SDR++,
  the ADS-B Exchange feed client) is pulled directly from its official
  source.

## Setup

```bash
git clone https://github.com/KC3WHJ/mint-sauce-for-ham.git
cd mint-sauce-for-ham
cp config.sh.example config.sh
nano config.sh   # fill in your callsign, grid square, radio serial ID, etc.
./Setup_Ham_Radio_Stack.sh
```

`config.sh` is git-ignored — your callsign, grid square, radio serial ID,
Winlink password, and VARA registration code never end up in version
control. Only `config.sh.example` (all placeholders) is tracked.

The script is safe to re-run — most steps check whether something's
already done before acting on it.

## Not fully hands-off

- The Wine installers (VarAC/VARA HF/VARA FM) launch interactively since
  their silent-install support was never verified — click through each
  wizard once when its window appears.
- The ADS-B Exchange feed installer is also interactive (whiptail dialogs
  asking for your station info).
- Leave `WINLINK_PASSWORD`/`VARA_REG_CODE` blank in `config.sh` to skip the
  sections that need them — a reminder is printed at the end telling you
  what's still unconfigured.
- `IC705_SERIAL_ID` is specific to one physical radio (its USB serial
  number) — the script tells you what it actually finds under
  `/dev/serial/by-id/` if the placeholder doesn't match.
- Only one of {VarAC, Pat Winlink HF, Pat Winlink FM, WSJT-X, JS8Call} can
  run at a time — they all share the one radio. Same for readsb vs. SDR++,
  and SDR++'s own VHF/UHF vs. HF/Shortwave modes — a single RTL-SDR dongle
  can only do one job at a time. The SDR++ shortcuts stop `readsb` for you
  automatically, but if you use `sudo systemctl stop readsb` by hand for
  any other reason, remember to start it again afterward or ADS-B tracking
  stays off.
- The script adds you to the `dialout` group so `rigctld`/flrig can open
  the IC-705's and a USB GPS's serial ports — **this only takes effect
  after you log out and back in (or reboot)**. Until then, radio control
  fails with `Permission denied`.
- VarAC is a .NET application and needs Wine Mono to run at all; the
  script installs a version confirmed working (older releases hit an
  internal Mono assertion crash on launch under Wine 9.0).
- flrig is only used for VarAC's PTT/CAT path — WSJT-X, JS8Call, and Pat
  all use direct `rigctld` instead, since flrig was previously found to be
  "a recurring, hard-to-diagnose source of hangs and crashes" for those.

## Fresh-install verification

Verified end-to-end on a freshly-installed Linux Mint 22.3 machine
(2026-09-05): every component — ADS-B/tar1090, the ADS-B Exchange feed,
both SDR++ modes, VarAC, VARA HF/FM, Pat Winlink HF/FM, WSJT-X, JS8Call,
and GridTracker — came up and worked correctly following this script plus
the one-time manual steps noted above (rebooting after the `dialout`
group change; entering registration codes; the interactive installer
wizards).
