#!/bin/bash
# Launches flrig for whichever radio is currently selected via
# select-radio.sh, pre-selecting it in flrig's own prefs file first so it
# always opens already pointed at the right rig -- and runs the audio sync
# too, so switching radios is one step (select-radio.sh), not several.
#
# A profile can also set FLRIG_BIN / FLRIG_CONFIG_DIR to use a separate
# flrig build and prefs directory entirely, if a radio ever needs its own
# patched/alternate flrig. Profiles that don't set these just use the
# system flrig and its default ~/.flrig directory.
set -e

ACTIVE="$HOME/radio_profiles/active-radio.conf"
if [ ! -e "$ACTIVE" ]; then
    echo "No radio selected. Run select-radio.sh first."
    exit 1
fi
source "$ACTIVE"

if [ -z "$SERIAL_DEVICE" ] || [ ! -e "$SERIAL_DEVICE" ]; then
    echo "ERROR: $RIG_NAME's serial device ($SERIAL_DEVICE) doesn't exist."
    echo "Is it plugged in and powered on?"
    exit 1
fi

FLRIG_BIN="${FLRIG_BIN:-flrig}"
FLRIG_CONFIG_DIR="${FLRIG_CONFIG_DIR:-$HOME/.flrig}"
FLRIG_PREFS="$FLRIG_CONFIG_DIR/flrig.prefs"

mkdir -p "$FLRIG_CONFIG_DIR"
if [ -f "$FLRIG_PREFS" ] && grep -q "^xcvr_name:" "$FLRIG_PREFS"; then
    sed -i "s/^xcvr_name:.*/xcvr_name:${FLRIG_NAME}/" "$FLRIG_PREFS"
else
    printf '; FLTK preferences file format 1.0\n; vendor: w1hkj.com\n; application: flrig\n\n[.]\n\nxcvr_name:%s\n' "$FLRIG_NAME" >> "$FLRIG_PREFS"
fi

# The rig-specific prefs file (e.g. IC-705.prefs) is where xcvr_serial_port
# actually lives - xcvr_name above only tells flrig which one to load.
# This used to be left alone, assuming whatever was last saved there (from
# a one-time manual GUI setup) would still be correct - but confirmed
# 2026-09-10 it isn't reliable: flrig can save xcvr_serial_port back to
# NONE on its own (seen after a failed "transceiver not responding"
# connection attempt), silently breaking every launch after that with no
# way to self-heal. Now force it to match the active profile's
# SERIAL_DEVICE on every launch, the same way rigctld/Pat/etc. never trust
# a possibly-stale saved value either.
RIG_PREFS="$FLRIG_CONFIG_DIR/${FLRIG_NAME}.prefs"
if [ -f "$RIG_PREFS" ] && grep -q "^xcvr_serial_port:" "$RIG_PREFS"; then
    # A plain `sed -i 's/^xcvr_serial_port:.*/.../'` corrupted this: FLTK's
    # own preferences format wraps long values (like this stable by-id
    # path) across multiple physical lines, continuation lines prefixed
    # with '+'. sed only replaced the first line and left the orphaned '+'
    # continuation line behind, so flrig read the two concatenated back
    # together into one garbled/duplicated path - confirmed 2026-09-11 via
    # a real "cannot open serial port" error with a visibly doubled device
    # name. Fixed by removing the key line AND any immediately-following
    # '+' continuation lines, then writing a single correct line back.
    RIG_PREFS="$RIG_PREFS" SERIAL_DEVICE="$SERIAL_DEVICE" python3 -c '
import os
path = os.environ["RIG_PREFS"]
value = os.environ["SERIAL_DEVICE"]
with open(path) as f:
    lines = f.readlines()
out, i = [], 0
while i < len(lines):
    if lines[i].startswith("xcvr_serial_port:"):
        out.append(f"xcvr_serial_port:{value}\n")
        i += 1
        while i < len(lines) and lines[i].startswith("+"):
            i += 1
        continue
    out.append(lines[i])
    i += 1
with open(path, "w") as f:
    f.writelines(out)
'
else
    echo "NOTE: $RIG_PREFS doesn't exist yet or has no xcvr_serial_port line -"
    echo "flrig hasn't been run for this rig before. Launch it once, set the"
    echo "serial port yourself in its Config/Setup/Transceiver menu, and this"
    echo "script will keep it pointed at the right device from then on."
fi

# Same self-reverting problem as xcvr_serial_port above, confirmed
# 2026-09-16 for the TX-500 MP: flrig writes restore_mode back to 1 on
# its own on exit no matter what a one-time edit sets it to, and with it
# on, flrig pushes its own remembered mode_A back to the radio on every
# connect - for the TX-500 MP this meant every launch silently kicked the
# radio out of DIG into USB, requiring a manual fix on the radio each
# time. Force it off on every launch instead of trusting a saved value,
# same reasoning as above. Opt-in per profile (FLRIG_DISABLE_RESTORE_MODE)
# since this hasn't been confirmed as an issue for other radios here.
if [ "$FLRIG_DISABLE_RESTORE_MODE" = "true" ] && [ -f "$RIG_PREFS" ] && grep -q "^restore_mode:" "$RIG_PREFS"; then
    sed -i "s/^restore_mode:.*/restore_mode:0/" "$RIG_PREFS"
fi

# Confirmed 2026-09-16 via ~/.flrig/trace.txt: the TX-500 MP's Kenwood
# TS-2000 CAT emulation over its 9600-baud DigiRig link can't keep up
# with flrig's default zero-delay polling of every parameter (S-meter,
# mode, bandwidth, volume, notch, squelch, RF gain, SWR, ALC, split,
# noise, tuner, PTT, etc. all polled every cycle) - commands and
# responses were visibly interleaved/mismatched in the trace (e.g. `S:
# PA; R: RL050`), which plausibly caused flrig to misread the radio's
# actual mode and push a wrong value back (see restore_mode fix above -
# that alone didn't stop the DIG->USB kick). Force a write delay so the
# radio has time to reply before the next command fires.
if [ -n "$FLRIG_SERIAL_WRITE_DELAY_MS" ] && [ -f "$RIG_PREFS" ]; then
    sed -i \
        -e "s/^serial_write_delay:.*/serial_write_delay:${FLRIG_SERIAL_WRITE_DELAY_MS}/" \
        -e "s/^serial_post_write_delay:.*/serial_post_write_delay:${FLRIG_SERIAL_WRITE_DELAY_MS}/" \
        "$RIG_PREFS"
fi
# The write delay above eats into serial_timeout's own budget for the
# radio's actual response - confirmed 2026-09-16 the default 50ms timeout
# wasn't enough headroom once 40ms (write+post-write) of delay was added,
# causing flrig to report "Transceiver Not Responding" even though the
# radio and port were both genuinely fine (confirmed via a direct rigctl
# test at the same time). Give it real headroom instead.
if [ -n "$FLRIG_SERIAL_TIMEOUT_MS" ] && [ -f "$RIG_PREFS" ]; then
    sed -i "s/^serial_timeout:.*/serial_timeout:${FLRIG_SERIAL_TIMEOUT_MS}/" "$RIG_PREFS"
fi

# Confirmed 2026-09-16: neither restore_mode nor the timing fixes above
# stopped the TX-500 MP silently dropping out of DIG into USB while
# connected to flrig - and the trace log conclusively showed flrig never
# sends an actual mode-SET command (only plain "MD;" reads, repeated
# every ~1.7s). A single manual read didn't flip it; sustained repeated
# polling over ~20s did. This points at a TX-500 MP firmware quirk in its
# Kenwood TS-2000 emulation - being repeatedly polled for mode seems to
# itself cause it to drop the DIG flag - not something fixable by
# changing what flrig sends. Testable/working around it by just not
# polling mode at all.
if [ "$FLRIG_DISABLE_MODE_POLL" = "true" ] && [ -f "$RIG_PREFS" ]; then
    sed -i "s/^poll_mode:.*/poll_mode:0/" "$RIG_PREFS"
fi

echo "Active radio: $RIG_NAME -- pre-selected in $FLRIG_BIN (config: $FLRIG_CONFIG_DIR)."

if [ -x "$HOME/.local/bin/sync-radio-audio.sh" ]; then
    "$HOME/.local/bin/sync-radio-audio.sh" || true
fi

exec "$FLRIG_BIN" --config-dir "$FLRIG_CONFIG_DIR"
