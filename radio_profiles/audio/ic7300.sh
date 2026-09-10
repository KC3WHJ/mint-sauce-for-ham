#!/bin/bash
# TX audio drive level for the IC-7300's own built-in USB audio codec.
# Unlike the FT-891/TX-500 MP's generic C-Media DigiRig codecs (Speaker/
# Mic/Auto Gain Control via amixer), this project drives this one via
# PulseAudio's sink volume directly - the codec's own ALSA mixer here
# doesn't expose useful separate playback controls the same way, and this
# is the exact level actually confirmed live over VARA HF via Pat Winlink
# on 2026-09-10 (ALC was barely moving at the previous default of 40%/
# -23.88dB; raised in two steps -- 75%/-7.50dB, then 90%/-2.75dB -- and
# 90% produced a real, successful VARA connection).
#
# Usage: ic7300.sh <card id> (unused here - kept for consistency with
# sync-radio-audio.sh's calling convention; this targets the PulseAudio
# sink by name instead, which is more robust than deriving it from the
# ALSA card id)
set -e

SINK="alsa_output.usb-Burr-Brown_from_TI_USB_Audio_CODEC-00.analog-stereo"

if ! pactl list short sinks | grep -q "$SINK"; then
    echo "WARNING: PulseAudio sink $SINK not found -- is the IC-7300 connected?"
    exit 1
fi

pactl set-sink-volume "$SINK" 90%
pactl set-sink-mute "$SINK" 0
echo "Set $SINK to 90% (-2.75dB) -- confirmed level for VARA HF TX drive."
