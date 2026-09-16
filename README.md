# mint-sauce-for-ham

One script to set up a full ham radio + SDR station on Linux Mint (or any
Ubuntu-based distro): ADS-B aircraft tracking, general-purpose SDR
reception, and a Wine-based digital-modes stack supporting multiple radios
(currently IC-705, IC-7300, FT-891, TX-500 MP, and G-90 — see
[Multi-radio support](#multi-radio-support)).

**Already set up and just want to know how to use everything?** See
[USER_GUIDE.md](USER_GUIDE.md) — what each application does and how to
run it day to day. This README covers installation, configuration, and
troubleshooting internals instead.

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
- **Fldigi, Flmsg, Flamp** (the rest of the Fldigi suite — Flrig is already
  covered above), **vARIM** (an open-source, Linux-native chat front-end
  for the VARA HF modem, alongside VarAC), and **CommStat** (a JS8Call
  situational-awareness companion/dashboard) — the rest of the AmRRON
  digital-comms toolset. See [AmRRON digital comms](#amrron-digital-comms)
  below.
- **VOACAP GUI** (`voacapgui`, from the PythonProp project) — HF
  propagation prediction, built on `voacapl` (the VOACAP engine ported to
  Linux). Both built from source (no apt package on this Ubuntu base).
- **A Conky station-status monitor** (top-right of the desktop) showing the
  active radio's name/frequency/mode, whether JS8Call/Pat Winlink are
  running, GPS grid square, and CPU temperature — plus a **10-minute
  station-ID timer** positioned directly beneath it (Start/Cancel buttons,
  beeps and flashes at each 10-minute mark, auto-repeats until cancelled).
  Both autostart on login.
- **chrony, configured to use the USB GPS as a time source** alongside
  normal internet NTP — accurate time with zero internet dependency, which
  matters more for off-grid/emergency-comms use (AmRRON, etc.) than for
  FT8 specifically (plain NTP already comfortably beats FT8's ~0.5s
  tolerance). See "Hard-won lessons" below for the real gpsd/chrony
  integration gotchas this required — the naive setup silently does
  nothing.

## AmRRON digital comms

AmRRON (American Redoubt Radio Operators Network) is a nationwide,
preparedness-oriented amateur radio network — organized nets, standardized
procedures, and an emphasis on training across several digital-mode
"layers" rather than locking into one, since signal conditions, urgency,
and available hardware all vary. This station's toolset covers all five
tools from AmRRON's own published priority order (Aug 2023, "Digital modes
– what order should I prioritize?"): **Fldigi → Flmsg → Flamp → JS8Call →
CommStat**, plus **VarAC**/**vARIM** (VARA's two front-ends) for
higher-throughput chat when conditions allow it.

**Compiled 2026-09-13 from amrron.com postings and other public
documentation — AmRRON's net schedules, frequencies, and tool versions
change over time. Treat the specifics below as a starting point, not a
substitute for amrron.com's current SOI (Signal Operating Instructions).**

- **Waterfall placement** — AmRRON convention keeps Fldigi-based traffic
  around 1000–1500 Hz and JS8Call traffic around 1900–2300 Hz on the same
  frequency, specifically so they don't collide. Set JS8Call's passband
  center via its own "Center" field; this isn't something the setup script
  hardcodes, since it's an operating-time choice per net, not an install
  default.
- **JS8Call callsign group** — `@AMRRON` under Callsign Groups (already
  set in this station's `JS8Call.ini`) lets directed messages/queries
  reach the whole AmRRON group.
- **JS8Call netiquette** — during a scheduled digital net, don't transmit:
  disable Heartbeat/auto-reply and don't manually send SNR queries. Even
  with waterfall separation, a strong JS8 signal can still interfere with
  other stations copying Fldigi traffic on the same frequency.
- **Fldigi rig control** — this station's Fldigi uses the same shared
  `rigctld` bridge as WSJT-X/JS8Call/Pat (Hamlib → NET rigctl →
  `127.0.0.1:4532`), *not* flrig (flrig is reserved for VarAC — see
  [Multi-radio support](#multi-radio-support)), and launches via
  `Start_Fldigi.sh`/the Fldigi Desktop shortcut, which starts `rigctld`
  first if nothing's already using it — same as WSJT-X/JS8Call. This
  config is applied automatically by the setup script, **not** through
  Fldigi's own Configure dialog: its "Use Hamlib" checkbox has a real bug
  (confirmed 2026-09-13 — clicking it, including a pixel-precise
  synthetic click that ruled out a hit-testing issue, never actually
  toggles it), and the first-run wizard's callsign field silently failed
  to save too. The setup script patches `~/.fldigi/fldigi_def.xml`
  directly instead (`CHKUSEHAMLIBIS`, `HAMRIGDEVICE`, `HAMRIGMODEL`,
  `MYCALL`, `RECEIVERSID` for RX RSID so incoming Flamp transfers
  auto-detect) — but that file only exists after Fldigi has been launched
  and cleanly closed once (File → Exit; killing it early writes nothing
  at all), so the very first time, launch Fldigi, click through the
  wizard with any values, close it normally, then re-run the setup
  script to apply the real config.
- **vARIM vs. VarAC** — two different front-ends for the same underlying
  VARA HF modem, not competing modes: VarAC is Windows-polished (via
  Wine, already set up) with a broader feature set (HF/FM/satellite);
  vARIM is open-source and Linux-native, lighter-weight, HF-only. Both can
  run against the same VARA HF modem instance. vARIM's config
  (`~/varim/varim.ini`) is set up by the setup script with this station's
  callsign/grid and PTT via the shared `rigctld` bridge (port 4532) —
  vARIM's own man page (`man 5 varim`) doesn't fully clarify whether
  `rigctld`-based PTT and the separate `ptt-mode` setting are independent
  or one overrides the other, so verify PTT actually keys the radio on
  the first real transmission rather than assuming.
- **CommStat** — the modern, actively-developed CommStat
  ([mgochoa57/CommStat](https://github.com/mgochoa57/CommStat), not the
  older CommStatOne), a situational-awareness dashboard that parses
  JS8Call's STATREP traffic and plots reporting stations on a map. It
  connects to JS8Call's own TCP API (`localhost:2442`), which the setup
  script enables (`TCPEnabled`/`AcceptTCPRequests` in `JS8Call.ini` —
  disabled by default). CommStat's own callsign/groups/QRZ-key settings
  need a one-time first-run setup through its own UI (Desktop shortcut) —
  not something safe to blind-patch into a config file.
- **Receive-only, no license needed** — JS8Call and CommStat both
  explicitly support running receive-only for situational awareness
  without being a licensed operator (a receiver or SDR is enough).

## Multi-radio support

This station runs more than one radio (currently an Icom IC-705, Icom
IC-7300, Yaesu FT-891, Lab599 TX-500 MP, and Xiegu G-90), each connected
via its own cable/interface. Rather than auto-detecting which one to use —
which breaks the moment two are plugged in at once —
`~/.local/bin/select-radio.sh` (installed by the setup script from `bin/`)
shows an explicit picker and points a symlink,
`~/radio_profiles/active-radio.conf`, at whichever one
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
`radio_profiles/ic705.conf`, `ic7300.conf`, `ft891.conf`, `tx500mp.conf`,
and `g90.conf` in this repo for real, working examples. Fields:

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
| `CIV_ADDR` | Radio's default CI-V address (e.g. `A4` for IC-705, `94` for IC-7300) — used by `channel-tools/` |
| `MEMORY_GROUPS` | `"true"`/`"false"` — whether this radio has grouped/banked memory (multi-band, e.g. IC-705) vs. a flat single-band memory space (e.g. IC-7300) — used by `channel-tools/`, see [Memory channel tools](#memory-channel-tools) |
| `NOTES` | Multi-line operator/panel-setting reminders, printed when you select this radio |

### Hard-won lessons (so you don't have to relearn them)

- **`voacapl`'s checked-in generated autotools files don't match this
  system's autoconf/automake versions — its own README's documented build
  steps fail with a real error, not a warning.** Confirmed 2026-09-13:
  `automake --add-missing && autoreconf` (as documented) produces
  `configure.ac:3: error: version mismatch. This is Automake 1.16.5, but
  the definition used by this AM_INIT_AUTOMAKE comes from Automake
  1.15.1` — the repo's committed `aclocal.m4` was generated with an older
  toolchain. Fixed with `autoreconf --install --force`, which fully
  regenerates `aclocal.m4`/`configure`/`Makefile.in` from the currently
  installed autotools instead of trying to patch around the mismatch.
- **CommStat's own `linuxinstall.sh` needs `python3-pip`, which it doesn't
  install itself and this machine didn't have.** Confirmed 2026-09-13: its
  Python installer (`install.py`) calls `pip`, and without the package at
  all fails with a generic-looking `ERROR: Could not install 'branca...'`
  that gives no hint the real problem is a missing `pip` binary entirely
  (`install.py` swallows the real subprocess stderr). The setup script
  installs `python3-pip` explicitly before running CommStat's installer.
- **Fldigi's first-run Configuration Wizard cannot be scripted through, and
  its own "Use Hamlib" checkbox is genuinely broken — the fix is to patch
  the XML config directly, not fight the GUI.** Confirmed 2026-09-13,
  found while actually setting up rig control on real hardware:
  1. Launching Fldigi for the first time opens a genuinely modal dialog
     (window title literally "Fldigi configuration wizard"), and no
     `fldigi_def.xml` gets written until it's clicked through — not even a
     graceful `wmctrl -c` window-close request (as opposed to a raw
     `SIGTERM`/`timeout` kill) produces a saved config, and the file only
     gets written on a genuinely clean exit (File → Exit) even from the
     main window afterward.
  2. Within that wizard, the "Use Hamlib" checkbox visually accepts
     clicks (it gains keyboard focus, shown by a dotted focus rectangle)
     but its checked state never actually changes — confirmed with a
     precision `python3-xlib` `XTest` synthetic click computed from the
     checkbox's exact on-screen pixel position (via `xwininfo` for the
     window's absolute origin, **not** `wmctrl -l -G` — see the
     `wmctrl` position caveat elsewhere in this file), which ruled out a
     simple click-coordinate/hit-testing miss on the user's end. This
     looks like a genuine bug in this Fldigi build (4.2.03), not user
     error.
  3. Separately, the wizard's callsign (`MYCALL`) field also silently
     failed to save, while `MYNAME`/`MYQTH`/`MYLOC` on the same page saved
     correctly — an inconsistent, narrower bug than #2, not the same
     root cause.
  4. The actual, reliable fix: complete the wizard once with throwaway
     values (finally makes `fldigi_def.xml` exist) and close Fldigi
     cleanly, then patch the real XML keys directly —
     `CHKUSEHAMLIBIS` (the broken checkbox, `0`→`1`), `HAMRIGDEVICE`
     (→ `127.0.0.1:4532`), `HAMRIGMODEL` (`2` = Hamlib's own "NET
     rigctl" model ID — already correct by default, confirmed via
     Hamlib's own model numbering, not guessed), `MYCALL`, and
     `RECEIVERSID` (RX RSID, `0`→`1`, for Flamp auto-detect). The setup
     script does this automatically once the file exists; see
     [AmRRON digital comms](#amrron-digital-comms).
  5. `rigctld` itself still needs to actually be running for any of this
     to matter — it's not a standalone daemon this project starts at
     boot, only on-demand by whichever app needs it (WSJT-X/JS8Call/Pat
     each start it themselves if nothing's listening on port 4532 yet).
     Fldigi now gets the same treatment via `Start_Fldigi.sh`/its Desktop
     shortcut — launching plain `fldigi` from an application menu entry
     that bypasses that wrapper will show the wrong frequency with a
     `Connection refused` in Fldigi's own console output, not because the
     Hamlib config above is wrong.
- **After a reboot, re-run Select Radio even if Conky already shows the
  right radio.** Confirmed by the user 2026-09-10: skipping this and
  opening VarAC directly after a reboot makes flrig throw an error, even
  though `radio_profiles/active-radio.conf` (a plain symlink) survives the
  reboot fine and Conky already reflects the correct radio from it.
  `select-radio.sh` itself only recreates that same symlink — it doesn't
  touch flrig, rigctld, or anything else — so simply re-selecting the
  already-active radio shouldn't change any on-disk state, yet it reliably
  avoids the error in practice. Root cause not identified; treat this as a
  real, reproducible requirement, not a superstition — always click
  through Select Radio once after every reboot before opening VarAC (or
  anything else that talks to the radio), regardless of what Conky
  already shows.
- **IC-7300's rear `[KEY]` jack defaults to "Paddle," not "Straight."**
  Confirmed 2026-09-10 after a full factory reset: plugging in a straight
  key while this is set to Paddle makes the internal electronic keyer
  interpret any contact closure as the dit paddle being held down, so even
  a light tap sends a rapid burst of dits instead of one. Fix:
  `MENU > KEYER > EDIT/SET > CW-KEY SET > Key Type` → change from Paddle
  to Straight. Same menu also has side tone, dot/dash ratio, and paddle
  polarity if those got reset too.
- **IC-7300's "DATA MOD" and "DATA OFF MOD" are independent settings for
  two different radio states, both under `MENU > SET > Connectors > MOD
  Input`.** Confirmed 2026-09-11 after a factory reset: WSJT-X keyed the
  radio fine (TX light on, correct USB-D mode on the radio's own display,
  PC-side audio confirmed perfect - PulseAudio stream unmuted at 100%,
  correctly routed) but ALC stayed completely flat - because **DATA MOD**
  (the input source used whenever the DATA function is ON, i.e. digital
  modes) was set to ACC instead of USB, so the radio was modulating from
  an unconnected port while genuinely-present USB audio was ignored
  entirely. Separately, **DATA OFF MOD** (the source used when DATA is
  OFF, i.e. normal voice) was set to USB, not MIC - meaning even a
  perfectly working microphone would've been ignored in plain voice mode.
  Set both explicitly and leave them: `DATA MOD = USB` (digital modes),
  `DATA OFF MOD = MIC` (voice). With both set correctly, switching between
  voice and digital modes is just toggling the DATA function - which
  WSJT-X/JS8Call/etc. already do automatically via CAT - no need to touch
  MOD Input again. This is a distinct setting from the mic-connector
  hardware fault covered elsewhere in this project's notes; check this
  first since it's pure configuration, not a physical fault.
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
- **gpsd + chrony integration has seven separate, non-obvious gotchas** —
  confirmed 2026-09-11/12 setting this up for real, across many rounds of
  "fixed it" that turned out not to be, including two that looked complete
  after a successful-seeming reboot and weren't. The setup script handles
  all seven, but if it's ever debugged again:
  1. **gpsd's SHM interface (the obvious first choice) doesn't work here.**
     gpsd exposes 12 SHM segments; units 0/1 are permanently root-only
     (0600) by design (legacy privileged-ntpd compatibility), and units
     2/3 are the unprivileged-accessible equivalent — but gpsd only
     populates *one* pair, whichever it has permission for based on what
     user *gpsd itself* runs as at that moment. gpsd briefly runs as root
     at startup (needed to open the raw device) and then drops privilege
     to an unprivileged `gpsd` system user (confirmed via `ps -o
     user,group -C gpsd` showing `gpsd dialout`, not root) — but the SHM
     segments get populated at whichever point in that sequence gpsd's
     NTP linkage code actually runs, which in practice was still only
     0/1, never 2/3, meaning chronyd (which also drops root, `+PRIVDROP`)
     can never read either pair. `ipcs -m` showing units 0/1 as `600` and
     2+ as `666` is the tell; `ntpshmmon` returning nothing for *any* unit
     (not just a permission error) is what confirms gpsd isn't writing to
     2/3 at all, not just that they're unreadable.
  2. **chrony's own FAQ recommends its SOCK interface over SHM anyway**
     (better security), which sidesteps the whole permission problem — but
     gpsd 3.25 (installed here) introduced *two* SOCK naming conventions:
     plain `/run/chrony.<name>.sock` is PPS-only, while NMEA-only
     ("clock") data — all a plain USB GPS puck without a PPS output pin
     has — needs `/run/chrony.clk.<name>.sock` instead (note the `.clk.`
     infix). Using the plain name with an NMEA-only GPS silently does
     nothing; no error on either side, the refclock just never shows
     reachability.
  3. **`<name>` in that socket path is whatever literal device path string
     gpsd itself was told to open the device with — gpsd doesn't
     canonicalize or resolve it, it just uses that exact string.** Get
     gpsd's own debug log (`gpsd -N -n -b -D 5 <device>`) to confirm the
     exact name it's actually looking for if `chronyc sources -v` ever
     shows `GPS` stuck at `Reach 0` with everything else seemingly right —
     don't trust an assumed socket filename.
  4. **gpsd must start *after* chronyd**, the reverse of normal boot order
     — SOCK requires gpsd to connect to a socket chronyd creates, so
     chronyd has to exist first. A systemd drop-in on `gpsd.service`
     (`/etc/systemd/system/gpsd.service.d/after-chrony.conf`,
     `After=chrony.service` + `Wants=chrony.service`) handles this; the
     setup script creates it.
  5. **Even with correct `After=`/`Wants=` ordering, there's still a real
     sub-second race** — confirmed 2026-09-12: on a clean boot, `gpsd`'s
     `ExecStart` ran essentially simultaneously with `chrony.service`'s
     own `ActiveEnterTimestamp`, not clearly after it. `After=` on a
     `Type=forking` service (chrony's type here) only guarantees "the
     forking parent process exited," not "chrony has finished creating
     the refclock SOCK file" — those aren't the same moment, and gpsd can
     win that race. Fixed with an `ExecStartPre` on gpsd's drop-in that
     actively waits (bounded to 10s, never fails gpsd's own startup if it
     times out) for the socket to actually exist before gpsd's real
     `ExecStart` runs.
  6. **Even with the socket correctly named, existing, and writable by
     plain Unix permissions, gpsd's writes to it were still silently
     failing — AppArmor, not DAC permissions, was the actual blocker.**
     Ubuntu ships an enforcing AppArmor profile for gpsd
     (`/etc/apparmor.d/usr.sbin.gpsd`) that only allows the legacy plain
     `chrony.tty*.sock` naming; it has no rule at all for gpsd 3.25+'s
     `chrony.clk.<name>.sock` convention (gotcha 2), regardless of what
     `<name>` is, so every write was denied before it ever reached a DAC
     check. The symptom was identical either way (`chrony_send(8)
     Transport endpoint is not connected`, errno 107, from gpsd's own
     debug log) — the only way to tell AppArmor apart from a permissions
     problem was `strace -f -e trace=connect` on gpsd, which showed the
     real syscall-level result: `connect(..., "/run/chrony.clk....sock",
     ...) = -1 EACCES`, and separately, `journalctl -k | grep
     apparmor.*gpsd` showing `apparmor="ALLOWED" operation="sendmsg"
     class="file" ... requested_mask="w"` entries once the profile was
     put into complain mode (`aa-complain`) to confirm AppArmor — not a
     socket file permission — was the thing standing in the way. Fixed
     with a local override (`/etc/apparmor.d/local/usr.sbin.gpsd`, the
     package's own designated site-override include, so it survives a
     gpsd package upgrade) adding `/{,var/}run/chrony.clk.*.sock rw,`,
     reloaded via `apparmor_parser -r /etc/apparmor.d/usr.sbin.gpsd`; the
     setup script does this automatically.
  7. **The big one: gpsd only reliably sets up the chrony SOCK link for a
     device it opens directly at its OWN startup — a device attached
     later via udev hotplug (gpsd's normal, default behavior: USBAUTO +
     a udev rule that runs `gpsdctl add`) never gets linked, no matter how
     correctly every other gotcha above is fixed.** This is what made the
     previous six look solved after a successful reboot and then fail
     anyway: gotchas 1-6 were all real and all necessary, but every live
     test and even a from-cold reboot kept showing `GPS` stuck at
     `Reach 0` until this was found. Confirmed by direct, repeated A/B
     comparison 2026-09-12: dozens of `gpsdctl add` attempts (manual, and
     via udev automatically on a real reboot, with gotchas 1-6 already
     fixed and double-checked via `journalctl -k | grep apparmor` showing
     zero denials) consistently left `Reach 0`, while configuring the
     device to be opened directly by gpsd's own `ExecStart` instead —
     via `DEVICES="<by-id path>"` in `/etc/default/gpsd`, the traditional
     static-device config most hotplug-oriented guides skip — worked
     immediately and reliably, reaching `Reach 377` (fully saturated)
     within a couple of poll intervals. An earlier fix attempt chased a
     *plausible-looking but wrong* theory here: that only `gpsd.service`
     itself needed `After=chrony.service`, not the separate
     `gpsdctl@<tty>.service` unit that udev actually triggers to do the
     "add" — ordering that unit after chrony too (confirmed via
     `journalctl -b -u 'gpsdctl@ttyACM0.service'` showing it then
     correctly running after chrony on a reboot, instead of 14+ seconds
     before) still left `Reach 0`. The ordering fix wasn't wrong to try,
     but it wasn't the actual mechanism — a hotplug-attached device
     apparently just doesn't get the chrony link set up regardless of
     *when* it's attached. `USBAUTO` stays enabled in `/etc/default/gpsd`
     (harmless, and still useful if the GPS is ever unplugged/replugged
     for non-NTP purposes like the ADS-B feed), but it's the static
     `DEVICES` line doing the actual work here.
  8. **A seemingly-reasonable refclock tuning parameter introduced a
     rock-solid, systematic ~926ms time error.** chrony's `offset`
     refclock parameter applies a fixed correction to every sample, meant
     for plain serial NMEA refclocks with a known one-NMEA-cycle lag —
     it does not apply to gpsd's SOCK feed, since gpsd already timestamps
     each fix itself before forwarding it. An earlier version of this
     setup added `offset 0.9999` anyway (copied from a generic
     NMEA-refclock example), which produced a suspiciously *exact and
     noise-free* `-926ms` reading in `chronyc sourcestats` (std dev only
     ~800µs) once gotchas 1-7 were finally all fixed — tight, consistent
     jitter like that from GPS is a tell that the bias is a config
     mistake, not a hardware/precision problem. Removing the `offset`
     parameter entirely dropped the reading to a steady ~80ms with ~1ms
     jitter, consistent with normal USB-serial + gpsd processing latency
     for a non-PPS GPS puck, and well within what FT8 needs.
- **Conky can crash at autostart on some boots** — confirmed 2026-09-12
  via a core dump (`coredumpctl gdb conky`, `bt`): it calls
  `XGetWindowProperty` while walking the window hierarchy to find the
  desktop window to draw on, and if that races against the desktop/window
  manager not being fully ready yet at very early login, the X server can
  return a protocol error that aborts the whole process. Not a config
  problem (the exact same config file runs perfectly seconds later by
  hand) and not reliably reproducible — plenty of earlier boots this same
  session came up fine. The autostart entry now retries once after a
  5-second delay if the first attempt exits
  (`conky -c ... || (sleep 5 && conky -c ...)`) rather than silently
  staying gone for the rest of the session on the boots where it loses
  this race.

## Memory channel tools

`channel-tools/` is a separate, self-contained toolkit for programming
memory channels and browsing them from a desktop app — independent of the
main setup script above. **Two protocol backends, three radios — not
every radio this project supports.** It speaks Icom's CI-V protocol
(IC-705, IC-7300) or Yaesu's CAT protocol (FT-891), picked automatically
per the active radio's `PROTOCOL` setting. It does *not* work with the
G-90 or TX-500 MP (fails with a clear error rather than doing something
wrong — see `channel-tools/README.md`'s "Future work" section for what
adding those would take). Within that scope it reads whichever radio is
active in `radio_profiles/active-radio.conf`, same as everything else in
this project — the IC-705 gets all 16 channel groups including VHF/UHF
repeaters; the IC-7300 and FT-891 each get the 5 HF-only sections, since
neither has VHF/UHF or a memory-group concept at all. It can
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
- One of the supported radios (IC-705, IC-7300, FT-891, TX-500 MP, G-90)
  if you want the ham digital-modes stack — see
  [Multi-radio support](#multi-radio-support) for adding a different one.
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
./Setup_Ham_Radio_Stack.sh
```

No `config.sh` yet? The script notices and interactively asks for your
callsign, grid square, Winlink password, and VARA registration info, then
writes `config.sh` for you — review it afterward (especially
`AUDIO_DEVICE`/`IC705_SERIAL_ID`, which are hardware-specific and don't have
a good interactive default) before it's used for real. Prefer editing a file
by hand instead? `cp config.sh.example config.sh && nano config.sh` still
works exactly as before — the script just uses whatever's there.

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
- **The first time flrig is used with a given rig on a given machine, it
  needs one manual one-time setup step** - confirmed 2026-09-15, IC-7300 on
  a second machine. flrig stores each rig's settings (serial port, meter
  calibration, and more) in its own file (`~/.flrig/<FLRIG_NAME>.prefs`,
  e.g. `IC-7300.prefs`) that only flrig itself creates, the first time you
  configure that rig through its own GUI (Config → Setup → Transceiver -
  select the rig, set the serial port shown in `radio_profiles/*.conf`'s
  `SERIAL_DEVICE` and the baud rate, then close/apply). Until that file
  exists, `Start_Flrig_Radio.sh` has nothing to force-correct (see the
  "flrig can silently reset its own serial port" note above) and prints a
  note saying so, but still launches flrig anyway - which then fails with
  "Transceiver not responding" since no serial port is set for that rig at
  all. After this one-time step, the existing force-set logic keeps it
  correct automatically on every future launch, same as every other radio.
  This is why `IC-705.prefs`/`Xiegu-G90.prefs` already existing on a
  machine (from this exact step having been done for those rigs before)
  can make it easy to forget this is a real, required step for the *next*
  new rig added to a machine - it's not something `select-radio.sh` or any
  other script currently automates away.
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
- **That same fix had its own bug**: FLTK's preferences format wraps long
  values (like a stable `/dev/serial/by-id/...` path) across multiple
  physical lines, with continuation lines prefixed `+`. The `sed` used to
  force-set `xcvr_serial_port` only replaced the first line, leaving an
  orphaned `+` continuation line behind - flrig then read the two lines
  concatenated back together into one garbled, visibly-doubled device
  path and failed with "cannot open serial port." Confirmed 2026-09-11:
  intermittent because it only bit once flrig had previously saved the
  prefs file in wrapped form itself (which it does for long values), so
  it depended on whatever state flrig's last save had left behind - not
  something a reboot alone would reset, since the prefs file persists on
  disk. Fixed by replacing the `sed` with a small Python pass that removes
  the key line *and* any immediately-following `+` continuation lines
  before writing a single correct line back, instead of assuming the
  value is always exactly one physical line.
- **`radio_profiles/*.conf` (and `conky/id-timer.py`) are deployed with
  `cp -n` (no-clobber), which protects real customizations from being
  overwritten but also means a placeholder file deployed before a profile
  was ever filled in and verified upstream stays a placeholder forever** -
  even after `git pull` brings in the real, working version, since
  `active-radio.conf` symlinks to the *deployed* copy in `~/radio_profiles/`,
  not the repo's copy. Confirmed 2026-09-15 (IC-7300's first real
  end-to-end test on a second machine, the laptop): `~/radio_profiles/ic7300.conf`
  was still the literal `SERIAL_DEVICE="/dev/serial/by-id/CHANGE_ME"`
  placeholder from before the profile existed in verified form, while the
  repo's copy had long since been filled in and confirmed working. Symptom
  was misleading - rigctld/flrig failed silently (Pat Winlink's progress
  spinner did nothing, flrig showed no frequency), nothing pointed at a
  stale config as the cause. No automated fix for this one (unlike the two
  above) since there's no way to tell "still a placeholder, safe to
  overwrite" apart from "genuinely customized, don't touch" without some
  kind of marker - if you add a new radio profile to a machine that's
  never used it before, or pull a `git` update that meaningfully changes
  an existing profile, diff `~/radio_profiles/<radio>.conf` against
  `mint-sauce-for-ham/radio_profiles/<radio>.conf` and copy over by hand
  if they differ.

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

A third round (2026-09-10/11, same desktop station) added a fifth radio
(IC-7300) as the first flat-memory/HF-only radio this project has
supported, which surfaced real CI-V differences from every radio added
before it (see `channel-tools/README.md`'s "Grouped vs. flat memory"
section, and the "Hard-won lessons" above for the flrig prefs-wrapping and
DATA MOD/keyer-type findings). Verified end-to-end on real hardware: flrig
CAT connectivity, `rigctld`-direct control (WSJT-X/JS8Call/Pat), VARA HF
audio (both RX metering and, after finding the PC-side output level was
too low by default, TX drive confirmed via a real over-the-air VARA
connection), and memory-channel programming (53 HF channels programmed
and spot-checked directly against the radio with zero failures, later
extended to 83 with national nets and an AmRRON group — see
`channel-tools/`). The generalized `channel-tools/` toolkit itself (renamed
from `ic705-channel-tools/`) was regression-tested against the original
IC-705 to confirm the refactor didn't change its existing behavior.

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
