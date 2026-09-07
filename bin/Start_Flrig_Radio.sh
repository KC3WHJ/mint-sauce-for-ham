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

echo "Active radio: $RIG_NAME -- pre-selected in $FLRIG_BIN (config: $FLRIG_CONFIG_DIR)."

if [ -x "$HOME/.local/bin/sync-radio-audio.sh" ]; then
    "$HOME/.local/bin/sync-radio-audio.sh" || true
fi

exec "$FLRIG_BIN" --config-dir "$FLRIG_CONFIG_DIR"
