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
- **A Conky station-status monitor** (top-right of the desktop) showing the
  active radio's name/frequency/mode, whether JS8Call/Pat Winlink are
  running, GPS grid square, and CPU temperature — plus a **10-minute
  station-ID timer** positioned directly beneath it (Start/Cancel buttons,
  beeps and flashes at each 10-minute mark, auto-repeats until cancelled).
  Both autostart on login.

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
- **The ADS-B Exchange installer's auto-generated feeder/site name is not
  reliably correct**, and if you run more than one feeder (e.g. a laptop and
  a desktop station both feeding at once), each needs its own distinct
  name — reusing one across two active feeders makes them indistinguishable
  on the sync check/MLAT map. It's come up with a different wrong value on
  every install so far (`EE-KPNE`, then `EE-DT-KPNE`). Set
  `ADSB_FEEDER_NAME` in `config.sh` to your station's real name and the
  setup script corrects it automatically via `~/fix-adsb-feeder-name.sh`
  (usage: `sudo ~/fix-adsb-feeder-name.sh EE-YOURNAME`), printing a reminder
  if it doesn't match yet.
- **`rigctld` can wedge** — stay running and still listening on port 4532,
  but stop actually answering any query (a plain `rigctl f` hangs
  indefinitely instead of erroring). Not fully solved as of 2026-09-10;
  here's what's actually confirmed so far, and what isn't:
  - Caught via `rigctld -vvvvv`: WSJT-X (and other Hamlib NET rigctl
    clients - JS8Call, gqrx) sends `\get_powerstat` as part of its own
    connection handshake, which this Hamlib version implements for the
    IC-705 as CI-V `18` with *no* data byte. The IC-705's own CI-V
    reference only documents `00`/`01` (off/on) forms for `18` - there's
    no "just tell me the status" variant - so the radio always replies
    `NG` (command rejected) to it. Hamlib has a known history of removing
    `get_powerstat` entirely for other Icom models with this same gap
    (ID-5100/ID-4100/ID-31/ID-51, per its NEWS file); as of the Hamlib
    version installed here, the IC-705 (model 3085) hasn't gotten the same
    treatment.
  - Turning off the IC-705's `CI-V Transceive` setting (ON by default;
    Menu → Set → Connectors → CI-V → CI-V Transceive → OFF, or remotely
    over CI-V with `1A 05 0131 00`) looked like a full fix in one test
    session (stable across several `rigctld` restarts) but was
    **disproven** in the next one - WSJT-X still triggered the same `18`
    rejection and wedge with Transceive confirmed off. It may still be A
    contributing factor, just not THE fix on its own.
  - Bottom line: the `\get_powerstat` rejection is real and reproducible,
    but doesn't fully explain why it's sometimes tolerated (rigctld/the
    app carries on fine) and sometimes wedges the whole connection. Until
    that's understood, treat this as a known rough edge, not solved.
  - Practical mitigation in place: `Start_WSJTX.sh`/`Start_JS8Call.sh`
    retry once (kill + fresh rigctld start) before giving up, and every
    direct `rigctl` call in `Setup_Ham_Radio_Stack.sh`'s generated
    launchers is `timeout`-wrapped so a wedge hangs a launcher for a
    bounded few seconds instead of forever. If a launcher still fails
    after the retry, `pkill -f "^rigctld "` and try again by hand usually
    clears it - radio hardware is never affected. The **Fix Rig Control**
    Desktop shortcut (`~/.local/bin/fix-rigctld.sh`) does exactly that
    `pkill` in one click, for whenever this comes up mid-session.
- **A shell `trap` for cleanup has to be registered before anything it's
  meant to clean up can fail** - not after, "once we're past the risky
  part." `Start_WSJTX.sh`/`Start_JS8Call.sh` originally registered their
  `trap cleanup EXIT` *after* the rigctld-start retry loop; when that loop
  hit the wedge above and exited on failure, the trap had never been set
  up yet, so cleanup() never ran and the freshly-started, wedged rigctld
  was left as an orphaned process. Fixed by registering the trap first,
  before rigctld is ever started.
- **VARA HF's auto-config step silently no-ops on every fresh install.** It
  edits `VARA.ini` to set the soundcard devices and registration code, but
  that file only exists after VARA HF has been launched at least once —
  and nothing in the script launched it first. VARA FM's equivalent section
  already force-launches it once to generate the file before editing
  (`timeout 8 wine ... || true`); VARA HF's was just missing the same
  step. Fixed by adding it. If you're on an older install where this
  already silently skipped, either re-run the script or open VARA HF once
  yourself, close it, then re-run.

## Memory channel tools

`channel-tools/` is a separate, self-contained toolkit for programming
memory channels over CI-V and browsing them from a desktop app —
independent of the main setup script above. Radio-neutral: it reads
whichever radio is active in `radio_profiles/active-radio.conf`, same as
everything else in this project. Works with the IC-705 (all 16 channel
groups, including VHF/UHF repeaters) and the IC-7300 (the 4 HF-only
sections, since it has no VHF/UHF or memory-group concept at all). It can
turn a RAINWorks-style "Standalone Analog Programming Guide" PDF into
memory channels automatically, or you can build/edit the channel CSVs by
hand. See [`channel-tools/README.md`](channel-tools/README.md) for the
full workflow, file layout, and known limitations (e.g. the radio must be
in MEMO mode on its own touchscreen for remote channel-switching to take
visible effect — there's no CI-V command to force that).

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
- `Start_WSJTX.sh`/`Start_JS8Call.sh` (Desktop shortcuts: WSJT-X, JS8Call)
  start `rigctld` first if nothing's using it yet, same as
  `Start_Pat.sh`/`Start_Pat_FM.sh` — unlike those, they never kill a
  pre-existing `rigctld`, since WSJT-X/JS8Call/Pat/Conky's display can all
  share one over the network at once, and only stop it again on exit if
  they're the one that started it (so a shared instance used by something
  else is never pulled out from under it).
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
- The script sets VarAC's rig control to flrig, and your callsign/grid,
  automatically (`VarAC.ini`'s `RigPTTControlType`/`RigFreqControlType`,
  `Mycall`, `MyLocator`) — same "force a first run to generate the config
  file, then edit it" pattern as VARA HF/FM above. VarAC has no
  registration code of its own (it's free) and no separate audio device
  setting either — it drives VARA HF as its modem engine, so VARA HF's own
  soundcard config is what actually matters for audio.
- **JS8Call's official GitHub `.deb` release is built against Qt6**, whose
  PipeWire/multimedia integration has a real bug ("Requested [input/output]
  audio format is not supported on device") with no working fix found.
  The distro repo build (what `apt install js8call` gets you) is Qt5 and
  confirmed working — that's what this script installs now, instead of a
  manually-downloaded `.deb`. WSJT-X's GitHub build happens to be fine too
  (also Qt5), but it's installed the same way for consistency. GridTracker
  has no distro repo package, so it's still the manually-downloaded `.deb`.
  General rule for this stack: prefer the distro repo over upstream `.deb`
  releases when both exist.
- **The ID timer's Start/Cancel buttons could silently stop responding
  to clicks** - confirmed and fixed 2026-09-10. It uses
  `overrideredirect(True)` + `-topmost` to stay always-on-top of normal
  windows, but overrideredirect takes a window out of window-manager
  management entirely, so `-topmost` only takes effect once at creation -
  it does not defend against falling behind later as other windows get
  raised. After a normal session of opening several other apps, the
  window was still being *drawn* on top (looked completely normal) but
  had silently fallen behind the desktop icon layer in the real X11
  input-stacking order, so clicks on Start/Cancel landed on the desktop
  instead of the buttons - invisible unless you specifically check window
  stacking (`Xlib`'s `query_pointer().child`), not just what's rendered.
  Fixed by having the window re-raise itself (`root.lift()`) every 3
  seconds via its own tick loop, rather than trusting the one-time
  `-topmost` hint to hold.
- **flrig can silently reset its own serial port to `NONE`** - confirmed
  2026-09-10, right after a "Transceiver not responding" connection
  failure (itself a one-off; the radio and port were both confirmed fine
  moments before and after with a raw CI-V test). Every launch after that
  failed the same way, since `Start_Flrig_Radio.sh` only pre-selects which
  rig to load (`xcvr_name` in `flrig.prefs`) and had always trusted that
  rig's own prefs file (`<RIG>.prefs`, e.g. `IC-705.prefs`) to still have
  the right `xcvr_serial_port` from a one-time manual GUI setup - with no
  way to self-heal once flrig overwrote it. Fixed the same way as every
  other "don't trust a possibly-stale saved value" spot in this project:
  `Start_Flrig_Radio.sh` now force-sets `xcvr_serial_port` to the active
  profile's `SERIAL_DEVICE` on every launch, not just `xcvr_name`.

## Fresh-install verification

Verified end-to-end on a freshly-installed Linux Mint 22.3 machine
(2026-09-05): every component — ADS-B/tar1090, the ADS-B Exchange feed,
both SDR++ modes, VarAC, VARA HF/FM, Pat Winlink HF/FM, WSJT-X, JS8Call,
and GridTracker — came up and worked correctly following this script plus
the one-time manual steps noted above (rebooting after the `dialout`
group change; entering registration codes; the interactive installer
wizards).

A second fresh-install test (2026-09-09), on a second machine (a desktop
station, separate from the original laptop this was first verified on —
this project now runs on both), found that the 2026-09-05 claim didn't
actually cover everything: the Conky monitor and ID timer had been
hand-built directly on the laptop's dotfiles and were never added to this
script, so they silently didn't appear on the fresh desktop install.
Fixed by adding the "Conky station-status monitor + 10-minute ID timer"
step above. Several more real bugs surfaced and were fixed the same
session:
- The ID timer's window position was first a coordinate hardcoded to the
  laptop's screen resolution (`1600x900`), landing off-screen on the
  desktop's different resolution; then, once made screen-relative, still
  overlapped Conky because its height was a rough guess (280px) far under
  Conky's real rendered height (377px). Now the timer queries Conky's
  actual live window geometry (`wmctrl` + `xwininfo`) at launch and
  positions itself flush beneath it, however tall it really renders.
- `fix-adsb-feeder-name.sh` (see "Hard-won lessons" above) went through two
  rounds: first it only matched one hardcoded wrong value (`EE-KPNE`) and a
  second install got a different wrong value (`EE-DT-KPNE`); then it turned
  out the *correct* value it was hardcoding a fix to (`EE-KPHL`) was
  actually the laptop's identity, not a universal answer — the desktop
  needs its own distinct name since both may feed at once. Now takes the
  name as an argument, driven by `ADSB_FEEDER_NAME` in `config.sh` (one
  value per machine, never committed).

## Backups

Not part of the setup script — a manual, per-machine step, but worth doing
before any major change (OS upgrade, new radio, etc.). The pattern used
successfully on this project's own machines:

```bash
BACKUP_DIR="/path/to/backup-destination/full-backup-$(hostname)-$(date +%Y%m%d-%H%M)"
mkdir -p "$BACKUP_DIR" && cd "$BACKUP_DIR"
sudo tar --listed-incremental=snapshot.file --acls --xattrs \
    --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run --exclude=/tmp \
    --exclude=/mnt --exclude=/media \
    --exclude=/lost+found \
    --exclude=/var/cache --exclude=/var/tmp \
    --exclude=/home/*/.cache --exclude=/root/.cache \
    --exclude=/home/*/.local/share/Trash --exclude=/root/.local/share/Trash \
    --exclude=/swapfile \
    -cpf - / 2> backup.log | zstd -T0 -o root-backup-full.tar.zst
```

This is a GNU tar `--listed-incremental` level-0 (full) backup, compressed
with zstd — keep `snapshot.file` around if you ever want to take a
incremental backup on top of it later (`tar --listed-incremental=snapshot.file
-cpf - /` again, same excludes, picks up only what changed). Restoring a
full backup **over a live, booted system is risky** — check the backup's
`etc/fstab` against the live system's real partition UUIDs (`blkid`)
before ever restoring `/etc/fstab` or `/boot/grub` verbatim, since a
mismatch (e.g. after a reinstall reformatted `/`) can break the
bootloader. Prefer restoring from a rescue/live USB, or restoring just
`~/` onto a fresh install and re-running `Setup_Ham_Radio_Stack.sh` for
everything else — this project's own machines don't keep any
system-level restore instructions in this public repo (they live in a
`README-RESTORE.txt` alongside each machine's actual backup archive,
off-repo, since that's where the archive itself is anyway).

What actually matters to back up for *this* project specifically, if you'd
rather not do a full-system image: `~/mint-sauce-for-ham/` (this repo
checkout, including the git-ignored `config.sh` and any radio-specific
`~/.flrig/*.prefs`), `~/radio_profiles/`, and `~/.claude/projects/` if
you're using Claude Code and want its per-project memory to survive too
(see the note at the very bottom of `~/.claude/projects/-home-ham/memory/MEMORY.md`,
if you've set one up, for where any additional resilient off-machine notes
live).
