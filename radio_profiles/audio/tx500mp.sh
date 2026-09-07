#!/bin/bash
# ALSA mixer levels specific to the Lab599 TX-500 MP over its Digirig
# Mobile audio codec -- the default levels are usually wrong for TX/RX
# audio on this radio. Levels are from a known-working reference config;
# control names below were corrected against this codec's real simple-mixer
# layout (`amixer -c <card>` showed just Speaker/Mic/Auto Gain Control, not
# the "Speaker Playback Switch"-style compound names an earlier draft of
# this script assumed). Adjust the percentages if the remote station can't
# decode you, or if you can't decode received audio.
#
# Usage: tx500mp.sh <ALSA card number>
set -e
CARD="$1"
if [ -z "$CARD" ]; then
    echo "usage: $(basename "$0") <ALSA card number>"
    exit 1
fi

amixer -q -c "$CARD" sset Speaker 92% unmute
amixer -q -c "$CARD" sset Mic 52% unmute
amixer -q -c "$CARD" sset Mic capture 31% cap
amixer -q -c "$CARD" sset 'Auto Gain Control' off

echo "Applied TX-500 MP amixer levels to card $CARD."
