# Detailed Steps — Audio Sync, TX-500 MP, Channel Exports, WebSDR JS8Call, G-90 Clicking, AmRRON Fldigi/Flmsg (2026-09-15 to 2026-09-18)

## 1. Audio settings weren't following the radio

Symptom: after switching radios, VARA and FLRIG audio devices had to be
re-entered by hand.

- `bin/select-radio.sh` now calls `sync-radio-audio.sh` right after
  writing the `active-radio.conf` symlink, so every consumer (VARA HF/FM,
  WSJT-X, JS8Call, Fldigi, Pat) is patched at the moment of selection.
- `Start_Fldigi.sh`, `Start_JS8Call.sh` and `Start_WSJTX.sh` never called
  the sync at all, and `Start_Pat.sh` / `Start_Pat_FM.sh` only did so in
  the already-deployed copies. The templates in `Setup_Ham_Radio_Stack.sh`
  that regenerate them on a fresh install were fixed to match.

## 2. Interactive `config.sh` on first run

`Setup_Ham_Radio_Stack.sh` used to exit with an error if `config.sh` was
missing and required a manual `cp config.sh.example config.sh` plus
edits. It now prompts for callsign, grid square, Winlink password and VARA
registration, and writes `config.sh` itself. Passwords are typed by the
user at first run and never committed.

## 3. IC-705 stuck in transmit (a bad cable)

VARA FM would lose signal when a transmission stopped or was cancelled and
the radio stayed keyed. Several wrong theories were chased and corrected:

- VARA's own PTT setting was inert VOX; the real PTT driver is Pat's
  `ptt_ctrl` via rigctld (`hamlib_rigs`, localhost:4532).
- VARA HF has no CAT/COM PTT dropdown at all, only RA-Board, by design.
  VARA FM does. This matches the user's long experience with both.
- VARA's CAT mode conflicts with rigctld because the COM port is
  exclusive under Wine.
- The IC-705's timeout timer (5 minutes) is the safety net.

Root cause: a failing USB cable. A replacement cable resolved it.

## 4. TX-500 MP audio: stable ID and mic level

- `radio_profiles/tx500mp.conf` and `ft891.conf` used `hw:1,0`. A
  reconnect moved the DigiRig to card 2, so the ALSA mixer script ran on
  the wrong device and left the real capture gain maxed (VARA HF input
  pegged in the red). Both profiles now use `hw:Device,0`, the card's ID,
  matching the IC-705 and IC-7300 convention. Rule: card and tty numbers
  are fragile; prefer `hw:<ID>,0` and `/dev/serial/by-id/`.
- `radio_profiles/audio/tx500mp.sh` mic capture went from 31% to 54%
  after live tuning: 31% gave about -30 dB, 54% gave about -24 dB,
  inside VARA HF's recommended range with headroom.

## 5. TX-500 MP: DIG kept turning into USB

Symptom: flrig (used by VarAC) switched the radio out of DIG into USB
within seconds, and flrig's saved rig selection reverted to TS-2000.

Root causes and fix, in order found:

- `FLRIG_NAME` was `"TX-500MP"`, not a real flrig driver name. flrig only
  offered the generic Kenwood "TS-2000" emulation and a dedicated native
  `TX500` (Lab599) driver. `Start_Flrig_Radio.sh` overwrote manual GUI
  fixes with the wrong name at every launch.
- `~/.flrig/trace.txt` showed the TS-2000 path never sent an explicit
  mode-set, so the drop wasn't flrig actively setting USB there.
- The radio's own CAT protocol (menu 36) was switched from TS-2000 to
  Lab599, flrig's rig to `TX500`, and the mode in flrig set to FSK-R so
  the radio maps to DIG.
- flrig rewrites some prefs on exit, so `Start_Flrig_Radio.sh` now forces
  the values that matter on every launch (`restore_mode`,
  `serial_write_delay`, `serial_timeout`, `poll_mode`), opt-in per profile
  through `FLRIG_*` flags in `tx500mp.conf`.
- rigctld (Pat, WSJT-X, JS8Call) was also moved from Hamlib's Kenwood
  emulation (model 2014) to the native LAB599_TX500 driver (model 2050).
  Reads, PTT and mode worked under either, but JS8Call's power slider sent
  a set-power command through the old driver that corrupted the radio's
  power state (RFPOWER read back as `-nan`; the radio keyed with no RF
  output). The radio's power is now set on the radio itself, and Pat
  Winlink HF, which never sets power via CAT, was confirmed working before
  and after.
- This radio must use 9600 baud.

The same change had to be reflected in the standalone Channel Picker
repo's docs.

## 6. TX-500 MP channel exports

Channel Picker cannot program the TX-500 MP directly (no CI-V, and its
native protocol is not a supported backend), so two exports were added to
`channel-tools/`.

- `export_tx500mp_csv.py`: converts a `channels_*.json` to the CSV that
  Lab599's TRX Remote Android app imports
  (`Channel,Name,Frequency,Mode,Filter,Power,ToneMode,ToneFreq,Offset`).
  Filter and Power are not in the source data, so they get a documented
  default.
- `export_tx500mp_bin.py`: writes the binary `.mem` for the TRX Mem
  desktop software, which programs the radio over USB. The format was
  reverse-engineered from real saved files: 100 fixed 6-byte records (a
  4-byte little-endian frequency in Hz, one ASCII mode digit, one ASCII
  PreATT digit). The channel number is the record's position and there is
  no name field. Mode digits: 0 unset, 1 LSB, 2 USB, 5 AM.
- A false start worth remembering: mode 0 displays as "USB" in TRX Mem's
  dropdown but is really unset and is not applied to the radio. Exports
  always write 2 for USB.
- Running TRX Mem under Wine: map the radio's serial device as a Windows
  COM port (`~/.wine/dosdevices/com50` symlinked to the tty), make the
  device accessible, then start the `.exe` with `wine start /Unix`. The
  COM number Wine actually used later differed, so verify the port in the
  app. Documented in `channel-tools/README.md`.
- On the radio: `CH` then left/right scrolls channels; `CH>VFO` copies a
  channel to the VFO. `VFO>CH` overwrites the channel, not the reverse.

## 7. Offline channel viewer for a phone

- Built with JDK 17, Android command-line tools, Gradle 9.7.1, AGP 9.4.0
  and Jetpack Compose. Read-only, no network permission.
- Channel numbering follows each radio (the IC-7300 and TX-500 MP start at
  00 or 01 to match the radio), and radios that can't be programmed this
  way show a short "channelization unavailable" note instead.
- Two variants: a public 3-radio version in the standalone Channel Picker
  repo, and a personal version kept out of both public repositories.
- Data separation rule: purchased commercial frequency data must not
  reach the public repo. Public data comes only from the public CSVs. Both
  READMEs link to the vendor's own page for users to obtain their own
  lists.

## 8. Receive-only JS8Call via a web SDR

Goal: decode JS8 from a web-based SDR with no radio, without any risk to
the radio-connected JS8Call.

- `Start_JS8Call_WebSDR.sh` creates a null sink (`websdr_sink`), starts
  `js8call -r WebSDR`, and after the browser is playing lists the audio
  streams in a `dialog` menu so you pick the WebSDR tab, then moves that
  stream into the sink with `pactl move-sink-input`.
- `Stop_JS8Call_WebSDR.sh` stops only that instance (matched by its
  distinct `-r WebSDR` flag) and unloads the sink.
- The profile `~/.config/JS8Call - WebSDR.ini` is pre-seeded: `Rig=None`,
  `SoundInName=websdr_sink.monitor`, `TCPServerPort=2443` (the real
  profile uses 2442), own UDP port.
- Desktop shortcuts: **Activate JS8Call WebSDR** and **Deactivate JS8Call
  WebSDR**, created by the setup script. Verified against a real public
  WebSDR through to actual decodes.

## 9. A separate CommStat for the WebSDR JS8Call

Attempted first: a second connector in the real CommStat. That doesn't
work well because JS8Call's API allows one client (`TCPMaxConnections=1`)
so whichever CommStat connects first wins, and Auto and RF Ack are
per-connector switches in one shared database (RF Ack would key
acknowledgements off traffic heard through someone else's receiver).

Adopted design: a fully separate copy.

- `Start_CommStat_WebSDR.sh` rsyncs the app into `~/CommStat-WebSDR`
  (a real copy, not symlinks: `commstat.py` resolves symlinks back to the
  original folder and `qrz_client.py` finds `traffic.db3` relative to its
  own file). The database and `config.ini` are excluded from the sync.
- On first run the copy's `traffic.db3` is seeded from the real one with
  SQLite's backup API (callsign, groups, QRZ settings, abbreviations
  carry over), then alerts, messages, STATREPs, videos, contacts and all
  connectors are deleted. One connector is added through CommStat's own
  `ConnectorManager`: `WebSDR`, 127.0.0.1:2443, Auto on, RF Ack off.
- `config.ini` is seeded with the opposite map theme of the real one as a
  visual cue, and `XDG_DATA_HOME` / `XDG_CACHE_HOME` point at
  `~/CommStat-WebSDR/.xdg` so the Qt WebEngine profile isn't shared.
- The script waits for port 2443 first, because CommStat only auto-connects
  at startup.
- The Activate script now runs the CommStat helper after JS8Call; the
  Deactivate script stops it by matching `CommStat-WebSDR/little_gucci.py`,
  which can never match the real CommStat's path.
- The WebSDR connector was removed from the real CommStat's database
  (backed up first), and its Station connector restored to Auto on, RF Ack
  on.
- `Setup_Ham_Radio_Stack.sh` regenerates all three scripts and installs
  `rsync`.

## 10. The G-90 clicking and flipping VFOs

Symptom: with the G-90 plugged in and JS8Call open, the radio clicked every
2-3 seconds, its frequency shifted between 14 and 7 MHz for about a quarter
second (VFO A vs B), and the CAT indicator went red.

What was ruled out: gpsd (no devices, CP210x rule disabled), ModemManager
(one probe at plug-in), any process holding the serial port, USB
disconnects, JS8Call's Split Operation (set to None, no change).

How it was found:

1. Closing JS8Call stopped the clicking, which made it look like JS8Call.
2. rigctld was restarted with `-vvvv` logging to a file. The log showed a
   fresh connection every couple of seconds, each followed by
   `icom_set_vfo` VFOA, VFOA, VFOB, VFOB, VFOA, VFOA.
3. Clicking was already happening with JS8Call closed, and `ps` showed
   short-lived `rigctl` processes launched by Conky.
4. Conky's `execi 2` scripts `ham-radio-freq.sh` and `ham-radio-mode.sh`
   ran `rigctl -m 2 -r localhost:4532 f` (and `m`) every 2 seconds. The
   `rigctl` client probes VFO A/B/A on every start; the G-90 audibly
   responds.

Fix: both scripts now send `f` and `m` over rigctld's raw TCP text port
with bash `/dev/tcp`, which sends no VFO probe, and still fall back to
flrig's XML-RPC. After the change the count of `icom_set_vfo` lines in the
debug log stopped increasing and the user confirmed the clicking was gone
with JS8Call running. The repo's `bin/` copies of both scripts were
updated and the README has a caveat: don't poll rigctld with the `rigctl`
client on a timer on Icom-style rigs.

## 11. AmRRON Fldigi + Flmsg: radio and receive-only WebSDR versions

Request: give Fldigi and Flmsg (AmRRON messaging) the same two capabilities
as JS8Call - correct per-radio configuration for the real radio, and an
isolated receive-only version fed from a WebSDR with Activate/Deactivate
icons. Reference material: AmRRON's video "FLDIGI Setup for AmRRON Ops |
Vid 2 | Receiving HF Digital Series" (the user saved its transcript and the
video's settings were applied from it) and the Fldigi help PDF.

Starting state found: the real `~/.fldigi` had just been regenerated with
untouched defaults - audio backend "File I/O" (no sound card), no rig
control, no callsign - so the radio version wasn't configured for anything
yet.

**Radio version**
- `Start_Fldigi.sh` now exports `PULSE_SOURCE`/`PULSE_SINK` from the active
  radio profile's `PULSE_INPUT`/`PULSE_OUTPUT`. Fldigi in PulseAudio mode has
  no per-device setting (it uses the server default), so the environment is
  the reliable way to aim it, and it follows Select Radio.
- On an untouched config it switches the audio backend to PulseAudio and
  rig control to the shared rigctld (Hamlib NET, 127.0.0.1:4532) - only when
  those keys are still at their first-run values, never over a choice the
  user made, and never while Fldigi is running (it rewrites its settings on
  exit).
- `bin/apply-amrron-fldigi.sh` applies AmRRON's settings from the video
  (applied once to the real Fldigi, guarded by a marker file): NBEMS/flmsg
  integration on (`AUTOEXTRACT`, `OPEN_FLMSG`, `FLMSG_TRANSFER_DIRECT`,
  `OPEN_FLMSG_PRINT`, `FLMSG_PATHNAME`), sweet spot off
  (`STARTATSWEETSPOT=0`), Rx ID on, AFC off, start mode Contestia 4/250
  (`Cont-4/250` in Fldigi's names) with waterfall at 900 Hz, and the three
  net frequencies added to `frequencies2.txt` (3.588, 7.110, 14.110 MHz).
  Tested first on a scratch copy of the config; a diff showed only the
  intended changes and a second run added no duplicates.
- New `Start_Flmsg.sh` and a Flmsg Desktop icon.

**Receive-only WebSDR version** (`Start_Fldigi_WebSDR.sh` /
`Stop_Fldigi_WebSDR.sh`, Activate/Deactivate Fldigi WebSDR icons)
- Separate folder `~/Fldigi-WebSDR` (Fldigi's `--home-dir`, `--config-dir`,
  `--flmsg-dir`), seeded once from the real settings, no rig control, audio
  in from `websdr_sink.monitor` and out to a discard sink (`websdr_txvoid`).
- Two Fldigis can't share the default XML-RPC port, ARQ port or SysV
  message-queue keys, so the copy uses 7363, 7323 and `--rx-ipc-key 9877
  --tx-ipc-key 6790`. Flmsg talks to Fldigi over XML-RPC as a client (its
  config has "Fldigi xmlrpc Addr/Port", default 7362), and its forms web
  page starts at port 8080 by default - Pat's port - so the WebSDR Flmsg gets
  `--server-port 8280`.
- Verified live: Fldigi records from the WebSDR sink and plays to the discard
  sink; ports as above; the real config files' checksums and timestamps were
  identical before and after.
- Visual cue: `-bg` colors do nothing in Fldigi, so the copy's callsign is
  the placeholder `WEBSDR-RX`, which shows in the title bar and taskbar.
- Fldigi asks "Confirm quit?" on a polite window close, so a Deactivate
  that asked it to close got stuck and fell back to killing it (losing its
  settings). Fixed by `CONFIRMEXIT=0` in the copy. Flmsg doesn't answer a
  close request at all, so Deactivate stops it directly.
- The Stop scripts share the audio sink: the JS8Call one keeps it while the
  Fldigi one runs and vice versa.
- Process-matching gotcha: `pgrep -f "fldigi .*--home-dir ..."` matched the
  shell command line of the test that contained the same text, so the Start
  script thought it was already running. Patterns are now anchored
  (`^fldigi --home-dir ...`) in the three scripts that use them.

**Flmsg first-run dialogs.** Flmsg blocks on a first-run "Select Default User
Interface" dialog (Service Agency / Simple vs Communicator / Expert), then
a configuration dialog. These are the user's one-time choices and aren't
scripted. A hand-written `FLMSG.prefs` (keys `xmlrpc_address`/`xmlrpc_port`
found in the binary) is seeded for the WebSDR Flmsg, but whether Flmsg reads
that file's format was not confirmed - if the WebSDR Flmsg's "Fldigi xmlrpc
Port" (Config) isn't 7363, set it there.

**AmRRON custom forms.** Flmsg lists custom forms only from the `CUSTOM`
folder of its data directory, so each Flmsg needs its own copy. The user
downloaded AmRRON's V5.0 set (STATREP V5.1, STATREP V5.00, SITREP, SPOTREP,
Blank Form, plus AmRRON's README; V5.00 STATREP is obsolete but kept to open
old traffic, per AmRRON) and installed it into both `~/.nbems/CUSTOM` and
`~/Fldigi-WebSDR/.nbems/CUSTOM` by hand (all three copies byte-identical).
The set is now in the repo (`amrron-forms/`, unmodified, with a README
crediting the source, amrron.com/amrron-forms). `bin/install-amrron-forms.sh`
copies them into a given Flmsg folder without overwriting anything, run by
`Start_Fldigi.sh`, `Start_Flmsg.sh` and `Start_Fldigi_WebSDR.sh`; the setup
script deploys the bundle to `~/.local/share/amrron-forms`.

**Setup script.** Generates `Start_Fldigi.sh` (with the per-radio audio,
AmRRON profile and forms block, taken from a quoted heredoc so its
variables stay literal), `Start_Flmsg.sh`, `Start_Fldigi_WebSDR.sh`,
`Stop_Fldigi_WebSDR.sh` and the three Desktop shortcuts. Verified by running
the script's own generator in a scratch home: the three new scripts are
byte-identical to the live ones, and the regenerated `Start_Fldigi.sh`
differs only by a cosmetic blank line.

**Not yet verified.** No form has been sent or received end to end (no
station to exchange with), and the browser-audio menu wasn't clicked
through for the Fldigi version.

## Other work this session, outside this repo

- Re-pairing the UV-PRO over Bluetooth and connecting it to YAAC (see the
  existing UV-PRO notes; its built-in KISS TNC needs no Direwolf).
