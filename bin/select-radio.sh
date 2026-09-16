#!/bin/bash
# Interactive radio picker, inspired by EmComm Tools' et-radio: lists every
# profile in ~/radio_profiles/*.conf, lets you explicitly choose one (rather
# than guessing from what's plugged in, which breaks if more than one radio
# is connected at once), and points radio_profiles/active-radio.conf at it.
# Also runs sync-radio-audio.sh immediately below, so VARA/WSJT-X/JS8Call
# are already correct before you launch anything. Every other script here
# (Start_Flrig_Radio.sh, Start_Pat.sh, Start_WSJTX.sh, ham-radio-name.sh,
# etc.) just reads that one active-radio.conf file too -- nothing else
# needs to change when you add a radio.
set -e

PROFILES_DIR="$HOME/radio_profiles"
ACTIVE_LINK="$PROFILES_DIR/active-radio.conf"

options=()
options+=("none" "No radio selected")
for conf in "$PROFILES_DIR"/*.conf; do
    [ -f "$conf" ] || continue
    [ "$(basename "$conf")" = "active-radio.conf" ] && continue
    name=$(basename "$conf" .conf)
    label=$(grep -m1 "^RIG_NAME=" "$conf" | cut -d'"' -f2)
    options+=("$name" "${label:-$name}")
done

SELECTED=$(dialog --clear --menu "Select the active radio:" 20 60 10 "${options[@]}" 3>&1 1>&2 2>&3)
exit_status=$?
clear

if [ $exit_status -ne 0 ]; then
    echo "No change made."
    exit 1
fi

if [ "$SELECTED" = "none" ]; then
    rm -f "$ACTIVE_LINK"
    echo "Active radio cleared."
    exit 0
fi

ln -sf "$PROFILES_DIR/$SELECTED.conf" "$ACTIVE_LINK"
source "$ACTIVE_LINK"

echo "Active radio set to: $RIG_NAME"
echo

# Sync VARA HF/FM and WSJT-X/JS8Call's audio device settings right now, so
# every app is already correct the moment you double-click its icon -
# don't rely on whichever launcher you happen to run first to do this (see
# sync-radio-audio.sh's own header for the "close VARA/WSJT-X/JS8Call
# first" caveat - if any of them are open right now, close and reopen
# after this to pick up the change).
if [ -x "$HOME/.local/bin/sync-radio-audio.sh" ]; then
    "$HOME/.local/bin/sync-radio-audio.sh" || true
    echo
fi

if [ -n "$SERIAL_DEVICE" ] && [ ! -e "$SERIAL_DEVICE" ]; then
    echo "NOTE: $SERIAL_DEVICE doesn't exist yet -- plug in/power on the radio."
    echo
fi

if [ -n "$NOTES" ]; then
    echo "Radio panel settings to check:"
    echo "$NOTES" | sed 's/^/  - /'
    echo
fi
