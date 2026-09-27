#!/bin/bash
# Runs alongside an active WebSDR session, undoing a PipeWire/PulseAudio quirk found live
# 2026-09-27: once one stream from an app (e.g. Firefox) is moved into websdr_sink,
# module-stream-restore remembers that per-APPLICATION (not per-tab/stream), so the NEXT new
# audio stream from that same app - an unrelated tab, e.g. YouTube playing alongside the WebSDR
# page - gets silently swept into websdr_sink too and goes silent, with nothing telling you why.
#
# Started (detached) by Start_Fldigi_WebSDR.sh right after it routes the WebSDR stream you chose;
# stopped by Stop_Fldigi_WebSDR.sh. Only that one stream ID is left alone - every OTHER stream
# that lands on websdr_sink is moved back to the sink that was your default at Activate time.
#
# Usage: watch-websdr-sink.sh SINK_NAME KEEP_STREAM_ID RESTORE_TO_SINK LOG_FILE
SINK_NAME="$1" KEEP_ID="$2" RESTORE_SINK="$3" LOG="$4"

sink_index() { pactl list short sinks | awk -v n="$SINK_NAME" '$2 == n {print $1; exit}'; }

pactl subscribe 2>/dev/null | while read -r line; do
    case "$line" in
        *"'new' on sink-input"*) ;;
        *) continue ;;
    esac
    id="${line##*\#}"
    [ -n "$id" ] || continue
    [ "$id" = "$KEEP_ID" ] && continue
    # Give PipeWire a moment to finish assigning the new stream's initial sink before checking it.
    sleep 0.3
    idx="$(sink_index)"
    cur="$(pactl list short sink-inputs | awk -v i="$id" '$1 == i {print $2}')"
    [ -n "$idx" ] && [ "$cur" = "$idx" ] || continue
    pactl move-sink-input "$id" "$RESTORE_SINK" 2>/dev/null \
        && echo "$(date '+%F %T') Stream #$id landed on $SINK_NAME on its own (PipeWire's per-app default) - moved back to $RESTORE_SINK." >> "$LOG"
done
