# Channel tools

Turns a RAINWorks-style "Standalone Analog Programming Guide" PDF into
memory channels, and gives you a desktop app to browse/jump to them by
name or group. **Two protocol backends, three radios total — not every
radio this project supports.** `program_channels.py` speaks either Icom's
binary **CI-V** protocol (`Radio` class — IC-705, IC-7300) or Yaesu's
plain-ASCII **CAT** protocol (`YaesuFT891Radio` class — FT-891), chosen
per-radio via `PROTOCOL` in `radio_profiles/*.conf` (`"civ"` or
`"yaesu_cat"`). **It does not work with the G-90 or TX-500 MP** (Xiegu and
Lab599 respectively — neither CI-V nor Yaesu CAT) — trying to use it with
one of those active radios fails with a clear "No channel map for
`<radio>`" error rather than attempting anything and getting it wrong.

The TX-500 MP does have two real, working paths to get channels
programmed today, just not through `program_channels.py`/Channel Picker
directly:

- **`export_tx500mp_csv.py`** converts a `channels_*.json` file into the
  CSV format Lab599's own **TRX Remote** Android app imports
  (`Channel,Name,Frequency,Mode,Filter,Power,ToneMode,ToneFreq,Offset`) -
  run it, get the CSV onto the phone running TRX Remote, and import it
  there. Filter and Power aren't tracked by Channel Picker's own channel
  data at all, so they're filled in with a documented default (FIL2 for
  CW, FIL1 otherwise; flat 10W) rather than left to guesswork per-channel
  - see the script's own docstring.

- **`export_tx500mp_bin.py`** converts the same source into the binary
  `.mem` format Lab599's **TRX Mem** *desktop* software uses (works
  directly with the radio over USB - no phone/Bluetooth needed). This
  format was reverse-engineered live 2026-09-16 from real saves, not
  guessed from a blank template - see the script's own docstring for the
  full byte layout. Two things worth remembering if this ever needs
  revisiting:
  - The format has **no room for a channel name** at all (600 bytes = 100
    fixed 6-byte records: 4-byte little-endian frequency + 1-byte ASCII
    mode digit + 1-byte ASCII PreATT digit, channel number is just the
    record's position in the file) - unlike the CSV/TRX Remote path,
    which does carry names. Cross-reference the channel number against
    Channel Picker or the CSV export to know what's programmed where.
  - **The mode byte's default/unset value (`0`) looks like "USB" in TRX
    Mem's own UI but isn't a real saved value** - a never-touched channel
    defaults to `0`, and the mode dropdown just shows its own first list
    item ("USB") for that, which is a UI default artifact, not a
    persisted encoding. This cost real back-and-forth: an earlier version
    of this script used `0` for USB based on exactly that dropdown
    display, silently writing every USB channel as "unset" instead.
    Confirmed correct via an explicit re-select (switch to a different
    mode, save, switch back to USB, save again - only then does the real
    byte value show up): **1=LSB, 2=USB, 5=AM** (CW/FM/DIG not confirmed -
    the script refuses to guess those, raising a clear error instead).

  **Running TRX Mem itself** (Windows-only, no native Linux build of the
  GUI app - there's a `Lab599-TRXMem-v1-03-x64` file alongside the .exe
  in the same download, but it's unrelated tooling, not a Linux port of
  the GUI): download from Lab599's site into `~/Downloads/Lab599-TRX-Mem-EN/`,
  then map the radio's serial port to a Wine COM port *before* launching
  (this uses the default `~/.wine` prefix, not `~/.wine32` - the prefix
  every other Wine app in this project uses for VARA/VarAC):
  ```
  sudo chmod 666 /dev/ttyUSB0          # or whatever the DigiRig enumerates as
  ln -s /dev/ttyUSB0 ~/.wine/dosdevices/com50
  ls -l ~/.wine/dosdevices/            # confirm the symlink
  cd ~/Downloads/Lab599-TRX-Mem-EN
  wine start /Unix "Lab599-TRXMem-1.03(x64).exe"
  ```
  Then in TRX Mem itself, select COM50 (or whatever port number was
  used) and connect. `chmod 666` bypasses `dialout` group permissions
  for a one-off session rather than needing a logout/login - being in
  the `dialout` group (which `Setup_Ham_Radio_Stack.sh` already adds
  this user to) should work too without the chmod, not independently
  confirmed. Prefer mapping the stable `/dev/serial/by-id/...` path
  instead of a raw `/dev/ttyUSB0` if doing this more than once - the
  same raw-index staleness this project has hit more than once tonight
  applies here too.

Within that scope, it reads whichever radio is active in
`~/radio_profiles/active-radio.conf` (the same file every other launcher
in this project uses) and picks the right protocol automatically. See
"Adding a radio" below for what a new radio needs — a new CI-V or Yaesu
CAT radio is mostly config (a new profile + channel map); a radio
speaking neither protocol means building a third backend from scratch.

## Files

- `channel_maps/<radio>.json` — one per radio, the source of truth for
  which CSV sections that radio gets and how they're organized: for each
  section, its display name, one-line description (shown in the picker's
  legend), which hardware memory group it lives in (0-99, grouped radios
  only — see below), and the channel number its group's slot numbering
  starts from.
- `*.csv` — one file per section, in the same column format as
  `wcs705_blank_template.csv` (RT Systems' WCS-705 import format). Shared
  across radios — a radio's map just decides which sections it uses.
- `channels_<radio>.json` — generated by `build_channel_index.py`, one per
  radio; this is what the channel picker actually reads. Never hand-edit it.
- `extract_pdf.py` — best-effort PDF-to-CSV extractor (see below).
- `build_channel_index.py` — rebuilds every `channels_<radio>.json` from
  the CSVs + `channel_maps/*.json` (all radios, one run).
- `program_channels.py` — pushes channels to whichever radio is active,
  over CI-V or Yaesu CAT per its profile's `PROTOCOL` (USB — close
  rigctld/flrig/WSJT-X/etc. first so the serial port is free).
- `channel-picker.py` — the desktop app. Needs `python3-tk` and
  `python3-serial`: `sudo apt install python3-tk python3-serial` on
  Debian/Ubuntu-based distros (not part of `Setup_Ham_Radio_Stack.sh`'s
  install list, so add them separately even if you're using this alongside
  that script).

## Grouped vs. flat memory — why there are per-radio maps at all

Icom radios speak two different CI-V memory dialects, set per-radio via
`MEMORY_GROUPS` in `radio_profiles/*.conf`:

- **Grouped** (`MEMORY_GROUPS="true"`, e.g. IC-705): multi-band radios with
  banked memory — CI-V selects a group first (cmd `08 A0`), then a channel
  within it (cmd `08`). Every VHF/UHF/HF section in `channel_maps/ic705.json`
  gets its own group.
- **Flat** (`MEMORY_GROUPS="false"`, e.g. IC-7300): single-band (HF/6m)
  radios have no group concept at all — cmd `08` selects a channel number
  (0001-0099) directly, confirmed against Icom's official IC-7300MK2 CI-V
  Reference Guide. Since there's nothing to group, `channel_maps/ic7300.json`
  only includes non-VHF/UHF sections (see below), and every section shares
  one `base_channel` so their slots land back-to-back in the flat 1-99 space
  instead of colliding — don't give a flat radio's sections per-section
  `base_channel` values copied from a grouped radio's map, or they'll all
  land on the same physical memories.

`program_channels.py`'s `Radio` class handles the CI-V-byte-level difference
in one place (`select_memory`); everything else (frequency/mode/tone
encoding) is standard CI-V shared across the whole Icom line.

## IC-7300 and FT-891: HF-only, so only the non-VHF/UHF sections apply

`channel_maps/ic7300.json` and `channel_maps/ft891.json` both include just
`HF_Nets_National`, `Time_Standard_Stations`, `Monitor_Only_Military_USCG`,
`Shortwave_Broadcast`, and `AMRRON_Nets` (83 channels total, landing in
physical memories 1-83) — neither radio can receive VHF/UHF at all, so the
repeater-list sections (`Fixed_Base_*`, `Local_Add-On_*`, `Extended_*`)
simply aren't offered for either. If you add a new HF-only section, add it
to both maps (same shared `base_channel` as the others); a VHF/UHF section
only needs adding to a grouped Icom radio's map.

**FT-891 specifics (Yaesu CAT, not CI-V):** confirmed live 2026-09-15, all
83 channels programmed with zero failures and spot-checked correct,
including on-air channel *names* (the `MT` command's TAG field — unlike
the IC-7300, the FT-891 has no name-write limitation at all). Scope
matches the IC-7300's own precedent: simplex only, no CTCSS/repeater-shift
wired up (nothing in these HF-only sections needs either). Two real
protocol quirks worth knowing if you touch `YaesuFT891Radio`: `MW`/`MT`/`MC`
give **no reply at all** on success despite what the manual's command
table implies (only an explicit `"?;"` rejection comes back, and
promptly) — `send_noreply()` exists because of this, and treating "no
reply" as a timeout is the natural-but-wrong first assumption. Separately,
`MT`'s *read* form echoes back the wrong channel number in its own reply
(always the last-*written* channel, not the one actually queried) even
though the rest of that reply's data is correct for the channel that was
actually asked about — not used by anything here (Channel Picker reads
names from `channels_<radio>.json`, never queries the radio live), so
left as a documented caveat rather than worked around.

**Known limitation, IC-7300 specifically: no custom on-radio channel name.**
This is a CI-V quirk of that one radio, not a general flat-memory
limitation — the FT-891 (also flat-memory, see above) has no such problem
and does support on-radio names. Frequency and mode program reliably
(confirmed live, 53/53 channels at the time, spot-checked across the full
range) via CI-V cmd `09` (copy VFO into the selected memory). Setting a
channel's *name* normally works by reading the memory's raw content (cmd
`1A 00`), patching the name bytes, and writing it back — this works on the
IC-705, but a real IC-7300 (confirmed 2026-09-10) rejects that write (NG
reply) the instant *any* byte differs from what it just read, even a
single character deep in the name field with everything else
byte-identical to a successful unmodified round-trip. Verified this isn't
a byte-offset or character-encoding bug (both checked against Icom's own
CI-V reference and cross-checked programmatically against the known-
correct frequency encoding) — whatever precondition this radio's firmware
actually wants isn't in the documentation as fetched, and further guessing
against live memory writes wasn't worth the risk. So on the IC-7300,
`program_channels.py` skips the name-write step entirely; the channel gets
the right frequency/mode, but its on-radio memory list will show the
radio's own default label, not the CSV's `Name`. The Channel Picker itself
is unaffected either way — it reads names from `channels_<radio>.json`, not
from the radio's own memory content.

## Getting a PDF to work from

This toolkit doesn't include a real "Standalone Analog Programming Guide" —
that's a commercial product. Get one for your own area directly from
RAINWorks LLC at <https://www.rainworksusa.com/standalone-programming-pdf>,
or use any similarly-tabulated repeater guide from another source; the
extractor works on any PDF matching the layout described below, not just
RAINWorks'. What
*is* included is `sample_guide.pdf` (source: `sample_guide.html`) — a small,
entirely fictional 10-channel example with the same table structure, purely
so you can test-drive `extract_pdf.py` without buying anything first:

```bash
python3 extract_pdf.py sample_guide.pdf /tmp/sample-output
```

## Workflow: starting from a new PDF

1. `python3 extract_pdf.py "/path/to/your/guide.pdf" .`
   (run from inside this directory) writes fresh `*.csv` files and a
   starter `channel_maps/<radio>.json`-shaped file into this directory,
   **overwriting what's there** — copy the directory elsewhere first if you
   want to keep the current set.
2. **Review the CSVs against the source PDF.** This is a text-layout parser
   tuned to RAINWorks' specific table format, not a guaranteed-correct PDF
   table reader. A differently-formatted PDF (different column order, extra
   columns, a scanned/image PDF instead of real text) will likely produce
   wrong or empty output — open a couple of the generated CSVs and
   spot-check frequencies/names/tones against the PDF by eye.
3. If a PDF doesn't match the expected layout at all, `extract_pdf.py` will
   say so plainly rather than silently producing garbage — in that case,
   build the CSVs by hand using `wcs705_blank_template.csv`'s column headers
   as your reference (an AI assistant reading the PDF's text alongside that
   template can usually do this transcription for you).
4. `python3 build_channel_index.py` — regenerates every `channels_<radio>.json`
   from whatever CSVs + `channel_maps/*.json` are currently in this directory.
5. Launch the picker (`python3 channel-picker.py`) to browse/verify.
6. `python3 program_channels.py` — writes everything to whichever radio is
   active to `~/radio_profiles/active-radio.conf`. Pass specific channel
   numbers (e.g. `python3 program_channels.py 58 59`) to (re)program just
   those, e.g. after editing one CSV row.

## Editing an existing channel, or adding/removing one

Edit the relevant section's CSV directly (it's a plain CSV, any spreadsheet
app or text editor works), then re-run steps 4-6 above. Channel numbers
just need to be unique within their section; a radio's `channel_maps/*.json`
entry's `base_channel` for that section determines which physical radio
slot number they land on (slot = channel_number - base_channel + 1). On a
grouped radio, slots only go 0-99 within a single hardware group, so a
section can't exceed 100 channels without needing its own additional group.
On a flat radio, slots share one 1-99 space across every section in that
radio's map (see "Grouped vs. flat memory" above) — the whole map can't
exceed 99 channels combined.

## Using the Channel Picker

Optional Desktop shortcut (create once):

```bash
cat > ~/Desktop/"Channel Picker.desktop" <<EOF
[Desktop Entry]
Name=Channel Picker
Comment=Browse and jump to programmed memory channels
Exec=python3 $HOME/mint-sauce-for-ham/channel-tools/channel-picker.py
Type=Application
Terminal=false
Icon=radio
Categories=HamRadio;
EOF
chmod +x ~/Desktop/"Channel Picker.desktop"
```

Point `Exec=` at wherever you actually keep this directory — don't deploy a
separate copy of the picker script or `channels_<radio>.json` elsewhere
(e.g. `~/.local/bin`), since that copy will silently go stale the next time
you add or edit channels here and rerun `build_channel_index.py`.

**The radio must already be in MEMO mode** (VFO/MEMORY icon → [MEMO] on the
touchscreen, or the MEMO button on radios with one) for "Go to Channel" to
actually change the displayed frequency. The memory-select commands on
both protocols (CI-V `08`/`08 A0`, Yaesu CAT `MC`) set which channel is
selected, but that only becomes visible/tuned if the radio's own
operating mode is already Memory rather than VFO — neither protocol has
a command to force that mode switch remotely (confirmed for the FT-891
too, not just assumed from the Icom side). If a selection silently does
nothing (or the radio briefly flashes a group number but the frequency
doesn't change), check the radio is in MEMO mode first.

**If `rigctld` or flrig is running, the picker stops it automatically before
sending its command** - confirmed 2026-09-10 that leaving either running
while the picker also opens the serial port directly corrupts both sides'
traffic (two processes writing raw bytes to the same physical UART at
once), and the picker's old error handling only caught an explicit NG reply
- a corrupted/timed-out reply slipped through as a false "success" message
with no actual effect on the radio. It does *not* restart whatever it
stopped afterward (it has no way to know if you want Pat/WSJT-X/Conky's
radio display back) - the status bar tells you what it stopped; restart it
yourself (e.g. re-launch Pat Winlink, or just source
`~/radio_profiles/active-radio.conf` and run `rigctld -m "$RIG_MODEL" -r
"$SERIAL_DEVICE" -s "$BAUD_RATE" -t 4532 &`).

## Adding a radio

**For an Icom radio (CI-V):**

1. Add a `radio_profiles/<name>.conf` entry (or extend an existing one) with
   `PROTOCOL="civ"`, `CIV_ADDR` (the radio's default CI-V address), and
   `MEMORY_GROUPS` (`"true"` if it's a multi-band radio with grouped/banked
   memory, `"false"` if it's single-band with flat 1-99 memory — check the
   radio's own CI-V reference guide for cmd `08`'s data format to be sure,
   don't assume).
2. Add `channel_maps/<name>.json` (matching `radio_key()`'s derivation —
   `"IC-7300"` → `"ic7300"`, lowercase with non-alphanumerics stripped) with
   whichever sections make sense for that radio (a VHF/UHF-capable radio can
   use any section; an HF-only radio only the non-VHF/UHF ones).
3. `python3 build_channel_index.py` to generate its `channels_<name>.json`.
4. Test frequency/mode programming on real hardware, single-channel first
   (`python3 program_channels.py <one channel number>`), before running the
   full batch — this project trusts real hardware over assumptions, and the
   IC-7300's CI-V quirks above (`0F`, `16 5D`, the name-write limitation)
   were each found exactly this way.

**For a Yaesu radio speaking the same CAT dialect as the FT-891** (steps
2-4 identical to above): add `PROTOCOL="yaesu_cat"` instead of the CI-V
fields. `YaesuFT891Radio` should work as-is for another radio using the
same `MW`/`MT`/`MC` command set and field layout, but verify against that
radio's own CAT reference book first — Yaesu's command set isn't
guaranteed identical across their whole line the way CI-V is across
Icom's, and this has only ever been confirmed against the FT-891 itself.

**For anything else** (Kenwood, a Yaesu radio with a meaningfully
different CAT dialect, Xiegu, etc.): means building a third protocol
backend from scratch — a new class alongside `Radio` and
`YaesuFT891Radio` in `program_channels.py`, plus the matching dispatch
logic in both that file's `main()` and `channel-picker.py`'s
`select_memory()`.

## Known limitations (not fixable via CSV/CI-V, by design)

- Channels with a cross-band RX/TX split larger than the duplex-offset
  mechanism supports (e.g. satellite/ISS crossband repeaters) can't be
  programmed this way — enter those manually on the radio.
- Per-channel TX-inhibit/receive-only isn't a CI-V-addressable memory
  attribute on these radios — set that manually for any channel you want
  receive-only, regardless of what a CSV's Comment column says.
- "FM-N" (narrow) rows program as plain FM — narrow bandwidth is a filter
  setting on these radios, not a distinct CI-V mode code.
- CTCSS/tone-squelch channels are only wired up for grouped radios (cmd
  `16 5D`, confirmed IC-705-specific — the IC-7300 uses different
  subcommands entirely and isn't implemented here, since no channel this
  toolkit has needed on an HF-only radio uses CTCSS). See "IC-7300" above
  for the separate, unrelated name-write limitation.

## Future work: G-90 and TX-500 MP

Scoped out 2026-09-15 (not implemented) - not full protocol
confirmations like the FT-891 section above, just what's known and what
would need live-hardware verification before writing real code. Both are
HF/6m-only like the IC-7300/FT-891, so both would likely reuse the same
`channel_maps/*.json` shape (5 public sections, flat 1-99 memory,
`MEMORY_GROUPS="false"`) - the actual work in both cases is the protocol
backend, not the channel data.

**G-90 (Xiegu) - genuinely speaks Icom CI-V, but confirmed NOT feasible
as of this unit's current firmware.** Live-tested 2026-09-15 (read-only,
non-destructive probes): basic CI-V rig-control commands work fine (cmd
`03` read frequency, cmd `04` read mode both returned real data). But
the memory-programming commands this toolkit actually needs don't -
**cmd `08`** (select memory channel) got no response at all, not even a
rejection, meaning the radio's CI-V firmware doesn't recognize it; **cmd
`1A 00`** (read memory channel content) got an explicit **NG (error)
reply** - recognized, but refused. So this isn't a "probably works with
minor changes" situation - it's confirmed blocked at the firmware level
unless Xiegu adds real CI-V memory support in a future update. Revisit
only if a firmware update specifically claims to add this, and re-test
the same way before assuming it works.

(Also resolved in the same session: the G-90 doesn't appear to validate
the CI-V destination address at all for basic commands - it replied
identically whether addressed as `0x70`, `0xa4`, `0x88`, `0x1d`, or
`0x19`. So the address inconsistency across sources noted originally
turned out to be a non-issue for read commands, though this was never
tested for writes and doesn't change the memory-command finding above.)

Background on why this looked promising before testing: `g90.conf`'s own
existing comment about flrig's Xiegu driver bug (hardcoded polling
address `0x88` instead of this radio's real `0x70`) and Hamlib's own
G-90 driver (`Hamlib/rigs/icom/xiegu.c`) living under the Icom backend
tree both pointed at real CI-V compatibility - which is true for basic
rig control, just not for memory programming.

**TX-500 MP (Lab599) - a genuine third protocol backend, comparable in
scope to today's FT-891 work.** Originally set up using **Kenwood
TS-2000 CAT emulation** (confirmed live 2026-09-15 via rigctld reading a
Kenwood `ID019` identification response) - not Icom CI-V, not Yaesu CAT.
**Switched 2026-09-16** to the radio's other CAT option, its **native
Lab599 protocol** (`tx500mp.conf`'s `MENU 36 CAT PROTOCOL` is now
`Lab599`, not `TS2000` - see that profile's `FLRIG_NAME` comment for
why: flrig's TS-2000 emulation path had a real, confirmed DIG->USB mode-
reversion bug that the native Lab599 driver didn't have). This means any
future channel-programming work here should target the **native Lab599
protocol**, not Kenwood TS-2000 - all of the Kenwood-specific research
below (PC Control Command Tables, `MR`/`MW`-style commands) is now
**moot** for that reason, not because it was wrong. The native Lab599
protocol's command format hasn't been researched at all yet - that's the
actual starting point now, not a continuation of the Kenwood work.
Before writing real code: find Lab599's own CAT/CI-V protocol reference
for the TX-500 (not the TS-2000's), confirm whether it exposes any
memory-channel commands at all (the G-90's experience this session is a
reminder that basic CAT support doesn't guarantee memory support), and
cross-check any field format against a real worked example the same way
the FT-891's `FA` worked example verified the frequency field width
there - don't hand-derive from a possibly-garbled table extraction
without a concrete worked example to check against, that's exactly what
cost the most time during the FT-891 implementation.

Neither is a quick follow-on to the FT-891 work: the G-90 is now
confirmed blocked at the firmware level (not a code problem to solve),
and the TX-500 MP is a full third-protocol-backend project. Both
conclusions came from putting real hardware in front of the question
rather than reasoning from driver source code or documentation alone -
same discipline as everywhere else in this toolkit.
