# Detailed Steps — Multi-Radio Support (2026-09-07)

## 1. Backup before prototyping

Per the user's request, a full system backup was taken to the external
drive before any architecture changes began, using the project's existing
`~/run-full-backup.sh` (`sudo tar --acls --xattrs` piped through
`zstd -T0`, verified with `zstd -t`).

## 2. Researching EmComm Tools OS

The user provided two release tarballs of EmComm Tools OS
(community.emcommtools.com), a separate Ubuntu 22.10-based ham radio
distro they already use successfully with the FT-891, TX-500 MP, and
G-90: a stable community release and a beta release specifically
containing TX-500 MP data the stable release lacked. Examined:

- `overlay/opt/emcomm-tools/conf/radios.d/*.json` — per-radio Hamlib
  model ID, baud rate, PTT type, and human-readable operator notes/field
  notes for the G-90, FT-891, and TX-500 MP.
- `overlay/opt/emcomm-tools/conf/radios.d/audio/*.sh` — per-radio ALSA
  mixer tuning scripts.
- `overlay/opt/emcomm-tools/sbin/wrapper-rigctld.sh` — confirmed EmComm
  drives every radio via direct `rigctld`, never flrig, which explains
  why flrig's known G-90 CI-V bug never surfaces for them.
- `overlay/opt/emcomm-tools/bin/et-radio`, `et-mode` — the explicit
  picker patterns the user asked to be emulated.
- `overlay/etc/skel/.conkyrc` — confirmed EmComm's Conky never live-polls
  CAT frequency/mode, only showing static/derived info — noted as the
  reason they never hit the Hamlib dual-VFO "clicking" issue this
  project's own live-frequency Conky feature can trigger.

Asked the user directly whether to adopt EmComm's JSON+jq profile format
or keep the project's existing plain-bash `.conf` convention;
recommended reuse (no functional benefit to JSON, avoids a new `jq`
dependency, avoids re-deriving/re-testing existing data) and the user
agreed.

## 3. Building the picker architecture

- `~/.local/bin/select-radio.sh`: lists every `~/radio_profiles/*.conf`
  in a `dialog` menu (reading each one's `RIG_NAME` for the label),
  symlinks `~/radio_profiles/active-radio.conf` to the chosen one, and
  prints that radio's `NOTES` field plus a warning if its
  `SERIAL_DEVICE` doesn't currently exist.
- `~/.local/bin/ham-radio-name.sh`, `Start_Flrig_Radio.sh`,
  `sync-radio-audio.sh` rewritten to source `active-radio.conf` directly
  instead of looping through all profiles guessing by device presence —
  the previous approach broke whenever two radios were plugged in at
  once.
- `sync-radio-audio.sh` gained a new `AUDIO_SCRIPT` hook: if a profile
  sets `AUDIO_SCRIPT`, the card number is parsed out of `AUDIO_DEVICE`
  (`hw:CARD,DEVICE`) via `sed` and the script is invoked with it, for
  radios needing one-time ALSA mixer tuning beyond just picking the
  right device name.
- Tested live end-to-end with the IC-705: picker → symlink → flrig
  launch (pre-selecting the radio in its own prefs) → audio sync → all
  four downstream config files updated correctly.

## 4. A gap found and fixed: Start_Pat.sh/Start_Pat_FM.sh

These two were still hardcoded to the IC-705's serial device from before
the picker existed. Left as-is, selecting a different radio in
`select-radio.sh` would have had no effect on what Pat Winlink actually
talked to. Rewrote both to source `active-radio.conf` the same way as
`Start_Flrig_Radio.sh`, folding in validation logic (checking for
placeholder `CHANGE_ME` values, checking the serial device exists) from
an earlier ad hoc multi-radio experiment (`Start_Pat_Radio.sh`, from
prior G-90 debugging), which was then deleted as redundant once its logic
was fully absorbed into the two canonical scripts.

## 5. G-90 profile

Rebuilt `radio_profiles/g90.conf` (deleted earlier in the project
alongside a patched flrig build that was abandoned after repeated
unexplained crashes) using EmComm's validated data: Hamlib model 3088,
19200 baud, PTT via RTS. This matched exactly what an earlier real test
this session had already proven working — a rigctld log showing a live
VARA HF connection attempt to another station, with the exact same
model/baud/PTT values. Real device paths (CP2102N serial, C-Media USB
audio codec) and VARA device names were pulled from that same session's
logs rather than re-derived. The profile documents the known flrig CI-V
bug risk for VarAC specifically, without attempting to re-patch flrig.

## 6. TX-500 MP: the RTS/CAT interference bug

With the TX-500 MP connected, CAT communication (Hamlib model 2014,
Kenwood TS-2000 emulation, 9600 baud) was completely silent — timeouts
on every query, with no response at any baud rate from 1200–57600, even
testing raw serial directly with pyserial (bypassing Hamlib entirely).

Ruled out one at a time: serial permissions and device enumeration (both
fine), the radio's own CAT protocol menu setting (user confirmed
`TS2000` after unplugging to check), and the physical cable/interface
(the user confirmed the exact same radio/cable/DigiRig combination
already works on another machine running EmComm Tools OS). Also
considered and ruled out a documented hardware quirk found via web
search — DigiRig Mobile's CAT interface needs an internal solder-jumper
enabling 3.3V isolation power, off by default before hardware revision
1.6 — since the unit was sealed and couldn't be opened to check, the
user's ability to test on the other machine was the deciding factor.

The actual cause: raising RTS (which is wired to this radio's PTT) at
the exact moment of reading a CAT reply was corrupting that reply with
transmit noise on the shared cable — confirmed once the user reported
seeing the radio key up (full-scale TX Dig Level deflection) during a
diagnostic RTS-toggle test, and reproduced consistently: garbled,
differently-corrupted 3-byte responses whenever RTS/DTR were touched,
versus a clean `ID019;` (Kenwood TS-2000 ID string) and correct live
frequency/mode from `rigctld` once RTS/DTR were left alone entirely.
Confirmed a dummy load was connected before any further RTS-toggling
tests, given the earlier confusion about what was actually keying the
radio.

## 7. TX-500 MP: audio

Real device paths confirmed with the radio connected: `/dev/serial/by-id/
usb-Silicon_Labs_CP2102N_...`, ALSA card 1 (`C-Media Electronics Inc. USB
Audio Device`), matching PulseAudio names. `radio_profiles/audio/
tx500mp.sh`'s amixer commands (copied from EmComm's reference script)
were checked against this codec's real `amixer -c 1` output and
corrected — the reference used compound control names like `Speaker
Playback Switch` that don't exist on this hardware; the real simple
controls are `Speaker`, `Mic`, and `Auto Gain Control`. Applied and
verified: Speaker 92%, Mic 52% playback / 31% capture, AGC off. Full
chain (`sync-radio-audio.sh`) tested live: WSJT-X/JS8Call `.ini`s and the
amixer script all updated in one pass. `Start_Pat.sh` tested live and
worked for Winlink HF, though VARA HF's own output device had to be set
manually once in its GUI since `VARA_INPUT`/`VARA_OUTPUT` weren't yet in
the profile — fixed immediately after by reading the value VARA itself
had saved and adding it to the profile.

## 8. FT-891

With the radio connected, CAT (Hamlib model 1036, 38400 baud, PTT via
`RIG` — CAT-commanded, matching the radio's `CAT RTS = DISABLE` menu
setting) worked cleanly on the first live test, reading real frequency
(7.190 MHz) and mode (`PKTUSB 3000`, matching the WDH=3000 setting just
configured on the radio). The radio's menu settings and physical
navigation steps (how to reach the WDH/bandwidth setting via the
FUNCTION-1 screen and MFK) were pulled from EmComm's `fieldNotes` and
added to the profile's `NOTES`.

A real mistake was caught here: the FT-891 was assumed to share the same
DigiRig Mobile interface as the TX-500 MP (based on device data queried
moments earlier, before the user had actually plugged the FT-891 in) —
the FT-891 actually uses a different, Yaesu-specific cable (the DR-891,
with a CP2105 dual-UART chip, distinct from the TX-500 MP's CP2102N),
which just happens to report an identically-named generic C-Media USB
audio codec. Corrected `SERIAL_DEVICE` once the real hardware was
queried; `AUDIO_DEVICE`/Pulse names turned out to still be correct by
coincidence of the shared generic codec name, not because it was the
same physical adapter.

Live-tuned mic capture gain against the user's own read of the VARA HF
input meter, iterating by direct percentage adjustment (100% default →
31% → "too low" → 66% midpoint → 77% → 80% → 86%, confirmed "fine").
Locked in as `radio_profiles/audio/ft891.sh` (Speaker 92%, Mic 52%
playback / 86% capture, AGC off) and wired into the profile's
`AUDIO_SCRIPT`. WSJT-X and JS8Call both launched and tested live —
confirmed changing frequency in one correctly updated the radio via the
shared `rigctld` instance and was reflected in the other.

## 9. Repository update

Copied the four real profiles, their audio scripts, and the four
picker/launcher scripts into the repo (`radio_profiles/`, `bin/`).
Rewrote `Setup_Ham_Radio_Stack.sh`'s `Start_Pat.sh`/`Start_Pat_FM.sh`
generation to produce the new active-radio.conf-based versions (falling
back to the IC-705 from `config.sh` if no radio has been selected yet,
so a fresh install still works before `select-radio.sh` has been run
once) and added a new section installing the picker scripts and any
profiles not already present. Updated `README.md` with a "Multi-radio
support" section documenting the profile format and the two hard-won
lessons above. Ran the established personal-info audit
(`git diff | grep -iE "<callsign>|..."`) before committing — clean.
Pushed as commit `9153b5e`.

## 10. Backup retry

The first backup attempt (kicked off in a backgrounded shell) failed
silently — `sudo tar` couldn't prompt for a password with no controlling
TTY, producing an empty 256KB archive that still reported "Integrity
check: OK" (zstd correctly validating an empty/near-empty stream, which
masked the real failure). Diagnosed via the actual `backup.log` showing
`sudo: a terminal is required to read the password`. Fixed by having the
user run `sudo -v` interactively first — but a second backgrounded
attempt still failed the same way, confirming the sandboxed shell runs
in a separate session with no shared TTY even after that. The user ran
`~/run-full-backup.sh` directly themselves instead, which succeeded:
5.7GB compressed, ~16.3GB uncompressed, verified with `zstd -t`.

## 11. Loose ends noticed along the way

- A leftover `js8call` process from an earlier live test was still
  showing as running in Conky after the window was closed — killed
  directly once noticed (same class of issue as an earlier `pat http`
  leftover found in prior sessions).
- Conky and the 10-minute ID timer utility were each found running as a
  process but not actually visible on screen (a stale/non-rendering
  instance) partway through this session — both fixed by killing the
  specific PID directly and relaunching fresh.
- This documentation folder itself was reviewed: the two 2026-09-05
  rebuild documents had the real callsign and grid square in plain text;
  replaced with redacted versions and the originals trashed (recoverable,
  not permanently deleted) — see the synopsis for this session for
  details.

## Final status

All four active radio profiles (IC-705, TX-500 MP, FT-891, and G-90's
rigctld path) are real, live-tested, and pushed to the repository. The
IC-7300 and (tr)uSDX profiles remain intentional placeholders per the
user's direction.
