#!/bin/bash
# Interactive radio picker, inspired by EmComm Tools' et-radio: lists every
# profile in ~/radio_profiles/*.conf, lets you explicitly choose one (rather
# than guessing from what's plugged in, which breaks if more than one radio
# is connected at once), and points radio_profiles/active-radio.conf at it.
# Start_Flrig_Radio.sh, sync-radio-audio.sh, and ham-radio-name.sh all just
# read that one file -- nothing else needs to change when you add a radio.
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

if [ -n "$SERIAL_DEVICE" ] && [ ! -e "$SERIAL_DEVICE" ]; then
    echo "NOTE: $SERIAL_DEVICE doesn't exist yet -- plug in/power on the radio."
    echo
fi

if [ -n "$NOTES" ]; then
    echo "Radio panel settings to check:"
    echo "$NOTES" | sed 's/^/  - /'
    echo
fi
