#!/bin/bash
# ALSA mixer levels specific to the Yaesu FT-891 over its DR-891 cable's
# C-Media USB audio codec (same generic codec as the TX-500 MP's DigiRig, so
# Speaker/Mic-playback levels are carried over from that known-good config;
# Mic capture was live-tuned for this radio specifically -- adjust further if
# the remote station can't decode you, or if you can't decode received
# audio.
#
# Usage: ft891.sh <ALSA card number>
set -e
CARD="$1"
if [ -z "$CARD" ]; then
    echo "usage: $(basename "$0") <ALSA card number>"
    exit 1
fi

amixer -q -c "$CARD" sset Speaker 92% unmute
amixer -q -c "$CARD" sset Mic 52% unmute
amixer -q -c "$CARD" sset Mic capture 86% cap
amixer -q -c "$CARD" sset 'Auto Gain Control' off
