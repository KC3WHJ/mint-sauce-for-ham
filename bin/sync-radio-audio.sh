#!/bin/bash
# Patches WSJT-X's, JS8Call's, and VARA HF/FM's audio device settings to
# match the currently-selected active radio (see select-radio.sh), instead
# of switching each app's audio device by hand every time you swap radios.
# Close all of them first -- they rewrite their own config on exit and
# would clobber this change if left running.
set -e

WSJTX_INI="$HOME/.config/WSJT-X.ini"
JS8CALL_INI="$HOME/.config/JS8Call.ini"
VARA_INI="$HOME/.wine32/drive_c/VARA/VARA.ini"
VARAFM_INI="$HOME/.wine32/drive_c/VARA FM/VARAFM.ini"

ACTIVE="$HOME/radio_profiles/active-radio.conf"
if [ ! -e "$ACTIVE" ]; then
    echo "No radio selected. Run select-radio.sh first."
    exit 1
fi
source "$ACTIVE"

if [ -z "$PULSE_INPUT" ] || [ -z "$PULSE_OUTPUT" ]; then
    echo "No PULSE_INPUT/PULSE_OUTPUT set for $RIG_NAME -- nothing to sync."
    exit 1
fi

echo "Active radio: $RIG_NAME"
echo "  WSJT-X/JS8Call input:  $PULSE_INPUT"
echo "  WSJT-X/JS8Call output: $PULSE_OUTPUT"
[ -n "$VARA_INPUT" ] && echo "  VARA input:  $VARA_INPUT"
[ -n "$VARA_OUTPUT" ] && echo "  VARA output: $VARA_OUTPUT"

if pgrep -x wsjtx > /dev/null || pgrep -x js8call > /dev/null; then
    echo "WARNING: WSJT-X and/or JS8Call is still running -- close it first or it will"
    echo "overwrite this change with its old settings when it exits."
fi
if pgrep -f "VARA.exe" > /dev/null || pgrep -f "VARAFM.exe" > /dev/null; then
    echo "WARNING: VARA HF and/or FM is still running -- close it first or it will"
    echo "overwrite this change with its old settings when it exits."
fi

for ini in "$WSJTX_INI" "$JS8CALL_INI"; do
    [ -f "$ini" ] || continue
    sed -i "s|^SoundInName=.*|SoundInName=${PULSE_INPUT}|" "$ini"
    sed -i "s|^SoundOutName=.*|SoundOutName=${PULSE_OUTPUT}|" "$ini"
    echo "Updated $ini"
done

if [ -n "$VARA_INPUT" ] && [ -n "$VARA_OUTPUT" ]; then
    for ini in "$VARA_INI" "$VARAFM_INI"; do
        [ -f "$ini" ] || continue
        sed -i "s|^Input Device Name=.*|Input Device Name=${VARA_INPUT}|" "$ini"
        sed -i "s|^Output Device Name=.*|Output Device Name=${VARA_OUTPUT}|" "$ini"
        echo "Updated $ini"
    done
fi

# Some radios need one-time ALSA mixer levels set on their audio codec
# (mic/speaker gain, disabling onboard AGC) beyond just picking the right
# device name -- see radio_profiles/audio/ for these.
if [ -n "$AUDIO_SCRIPT" ] && [ -x "$AUDIO_SCRIPT" ]; then
    CARD=$(echo "$AUDIO_DEVICE" | sed -n 's/^hw:\([0-9]*\),.*/\1/p')
    if [ -n "$CARD" ]; then
        "$AUDIO_SCRIPT" "$CARD"
    else
        echo "AUDIO_SCRIPT is set but couldn't parse a card number out of AUDIO_DEVICE=$AUDIO_DEVICE -- skipping."
    fi
fi
