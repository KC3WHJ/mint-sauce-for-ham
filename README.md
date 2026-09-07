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
  **WSJT-X**, and **GridTracker** — all sharing whichever radio is currently
  selected (see [Multi-radio support](#multi-radio-support) below) via a
  single Hamlib `rigctld` instance talking directly to its serial port.

## Multi-radio support

This station runs more than one radio (currently an Icom IC-705, Yaesu
FT-891, Lab599 TX-500 MP, and Xiegu G-90), each connected via its own
cable/interface. Rather than auto-detecting which one to use — which
breaks the moment two are plugged in at once — `~/.local/bin/select-radio.sh`
(installed by the setup script from `bin/`) shows an explicit picker and
points a symlink, `~/radio_profiles/active-radio.conf`, at whichever one
you choose. Every launcher script (`Start_Flrig_Radio.sh`,
`sync-radio-audio.sh`, `Start_Pat.sh`, `Start_Pat_FM.sh`) just reads that
one file — nothing else needs to change when you add a radio.

This design (an explicit picker + a stable "active radio" pointer, plus
printing operator notes when you pick one) is adapted from
[EmComm Tools OS](https://community.emcommtools.com)'s own `et-radio` and
`et-mode` selectors, though the underlying profile format here is plain
bash (`KEY="value"`, sourced directly) rather than EmComm's JSON, to avoid
a `jq` dependency and reuse this project's existing config style.

Each radio gets a profile at `radio_profiles/<name>.conf` — see
`radio_profiles/ic705.conf`, `ft891.conf`, `tx500mp.conf`, and `g90.conf`
in this repo for real, working examples. Fields:

| Field | Meaning |
|---|---|
| `RIG_MODEL` | Hamlib rig model ID (`rigctl -l` to list) |
| `RIG_NAME` | Display name |
| `SERIAL_DEVICE` | `/dev/serial/by-id/...` path (stable across reboots/re-plugs) |
| `BAUD_RATE` | Must match the radio's own CAT-rate menu setting |
| `PTT_TYPE` | Optional; `rigctld`'s `-P` flag (e.g. `RTS`, `RIG` for CAT-commanded PTT) |
| `AUDIO_DEVICE` | ALSA `hw:CARD,DEVICE` |
| `PULSE_INPUT` / `PULSE_OUTPUT` | PulseAudio device names, for WSJT-X/JS8Call |
| `VARA_INPUT` / `VARA_OUTPUT` | Wine-truncated WinMM device names, for VARA HF/FM |
| `FLRIG_NAME` | Rig name as flrig itself calls it (only needed for VarAC's path) |
| `FLRIG_BIN` / `FLRIG_CONFIG_DIR` | Optional: a separate flrig build/prefs dir for one radio |
| `AUDIO_SCRIPT` | Optional: path to a one-time ALSA mixer-tuning script (see `radio_profiles/audio/`) for radios whose default mic/speaker levels are wrong |
| `NOTES` | Multi-line operator/panel-setting reminders, printed when you select this radio |

### Hard-won lessons (so you don't have to relearn them)

- **Don't assert RTS/DTR while reading CAT.** If a radio's PTT line is
  wired to RTS (common for RTS-keyed rigs like the TX-500 MP), toggling RTS
  at the same moment you're trying to read a CAT reply dumps electrical
  noise onto the same cable and corrupts the response unpredictably —
  looks exactly like a wrong baud rate or a dead/flaky interface, but
  isn't. If CAT is timing out or returning garbage that's *differently*
  garbled every attempt, check whether whatever's testing it is also
  touching RTS/DTR.
- **flrig's Xiegu-G90 driver has a real bug**: it hardcodes the CI-V
  polling address for S-meter/attenuator commands to `0x88` instead of the
  G-90's actual `0x70`, which can eventually crash flrig. WSJT-X/JS8Call/Pat
  all talk to the G-90 via `rigctld` directly and are unaffected — only
  VarAC (the one app in this stack that needs flrig instead of `rigctld`)
  is at risk. `radio_profiles/g90.conf` documents this; the fix used to be
  a locally-patched flrig build, but that build was abandoned after further
  unexplained crashes, so this is currently unresolved upstream.
- **A shared DigiRig-style USB adapter reports the same `by-id` serial
  path regardless of which radio's cable is plugged into it.** If you swap
  radios on the same physical interface, don't assume yesterday's
  `SERIAL_DEVICE`/`AUDIO_DEVICE` values are still right for today's radio —
  re-check with `ls /dev/serial/by-id/` and `aplay -l` each time, ideally
  with only the one radio connected.
- **Generic USB audio codecs (e.g. C-Media chips used by many DigiRig-style
  cables) often ship with capture gain maxed out and AGC enabled**, both of
  which will peg a waterfall/level meter into the red. `AUDIO_SCRIPT` exists
  specifically for this — see `radio_profiles/audio/tx500mp.sh` and
  `ft891.sh` for the `amixer` pattern (check real control names with
  `amixer -c <card>` first; they don't always match what another config
  reference assumes).

## IC-705 memory channel tools

`ic705-channel-tools/` is a separate, self-contained toolkit for
programming the IC-705's memory channels over CI-V and browsing them from
a desktop app — independent of the main setup script above. It can turn a
RAINWorks-style "Standalone Analog Programming Guide" PDF into memory
channels automatically, or you can build/edit the channel CSVs by hand.
See [`ic705-channel-tools/README.md`](ic705-channel-tools/README.md) for
the full workflow, file layout, and known limitations (e.g. the radio must
be in MEMO mode on its own touchscreen for remote channel-switching to
take visible effect — there's no CI-V command to force that).

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
  `/dev/serial/by-id/` if the placeholder doesn't match. It's only used as
  the fallback default for `Start_Pat.sh`/`Start_Pat_FM.sh` before you've
  run `select-radio.sh` for the first time, or if you only ever use the one
  radio — see [Multi-radio support](#multi-radio-support) for anything else.
- Only one of {VarAC, Pat Winlink HF, Pat Winlink FM, WSJT-X, JS8Call} can
  run at a time — they all share the one radio. Same for readsb vs. SDR++,
  and SDR++'s own VHF/UHF vs. HF/Shortwave modes — a single RTL-SDR dongle
  can only do one job at a time. The SDR++ shortcuts stop `readsb` for you
  automatically, but if you use `sudo systemctl stop readsb` by hand for
  any other reason, remember to start it again afterward or ADS-B tracking
  stays off. `~/Desktop/Stop Pat Winlink.desktop` (or `~/.local/bin/stop-pat.sh`)
  stops Pat and whichever VARA engine it started, so it doesn't sit running
  unnoticed and conflict with the next app that needs the radio.
- `Start_Pat.sh`/`Start_Pat_FM.sh` set the radio's mode (USB-D for HF,
  FM for FM) before launching, since VARA HF and VARA FM each need a
  different one and won't correct it for you if it was left in the other's
  mode by a prior session.
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
