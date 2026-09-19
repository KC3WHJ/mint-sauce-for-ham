#!/bin/bash
# Applies AmRRON's recommended Fldigi settings to a Fldigi config folder
# (default ~/.fldigi), following AmRRON's "FLDIGI Setup for AmRRON Ops" video
# (Receiving HF Digital series, Vid 2). Idempotent - safe to run again.
# Used for both the real, radio-connected Fldigi (Start_Fldigi.sh, once) and
# the receive-only WebSDR copy (Start_Fldigi_WebSDR.sh, when it's seeded).
#
# Usage: apply-amrron-fldigi.sh [config-dir]
# Close Fldigi first if it's using that folder - it rewrites its settings on
# exit and would undo this.
#
# What it sets (video step -> fldigi_def.xml / fldigi.prefs key):
#   Misc > NBEMS interface: data-file interface on, "open with flmsg", "open
#     in browser" (print to browser), flmsg path -> AUTOEXTRACT, OPEN_FLMSG,
#     FLMSG_TRANSFER_DIRECT, OPEN_FLMSG_PRINT, FLMSG_PATHNAME
#   Misc > Sweet Spot: uncheck "always start new modems at these
#     frequencies" (otherwise a mode change snaps off the net's 900 Hz
#     waterfall position) -> STARTATSWEETSPOT=0
#   Save parameters: config and macros saved on exit -> SAVECONFIG, SAVEMACROS
#   Rx ID on (lets a sending station switch your mode, e.g. to MFSK32 for
#     traffic, then back to Contestia) -> RECEIVERSID=1
#   AFC off; start on Contestia 4/250 with the waterfall carrier at 900 Hz
#     -> fldigi.prefs afc_enabled/afconoff, mode_name, wf_carrier
#   Frequency list: AmRRON net frequencies - 80m 3.588, 40m 7.110, 20m
#     14.110 MHz, each Contestia 4/250 at 900 Hz -> frequencies2.txt
#
# NOT set (per-station, by hand): callsign/name (a tactical call or N0CALL is
# fine when receiving only), squelch level (set it against your real noise
# floor - see the video), and the audio device (Start_Fldigi.sh /
# Start_Fldigi_WebSDR.sh pick it through PULSE_SOURCE/PULSE_SINK instead).
set -e

CFG="${1:-$HOME/.fldigi}"
XML="$CFG/fldigi_def.xml"
PREFS="$CFG/fldigi.prefs"
FREQS="$CFG/frequencies2.txt"

if [ ! -f "$XML" ]; then
    echo "No $XML - run Fldigi once (File > Exit to close it) first."
    exit 1
fi

set_xml() {  # key value
    if grep -q "^<$1>.*</$1>" "$XML"; then
        sed -i "s|^<$1>.*</$1>|<$1>$2</$1>|" "$XML"
    else
        echo "  (skipped $1: not in this Fldigi's config)"
    fi
}
set_pref() {  # key value  (fldigi.prefs is key:value lines)
    [ -f "$PREFS" ] || return 0
    if grep -q "^$1:" "$PREFS"; then
        sed -i "s|^$1:.*|$1:$2|" "$PREFS"
    fi
}

set_xml AUTOEXTRACT 1
set_xml OPEN_FLMSG 1
set_xml FLMSG_TRANSFER_DIRECT 1
set_xml OPEN_FLMSG_PRINT 1
FLMSG_BIN=$(command -v flmsg || true)
[ -n "$FLMSG_BIN" ] && set_xml FLMSG_PATHNAME "$FLMSG_BIN"
set_xml STARTATSWEETSPOT 0
set_xml SAVECONFIG 1
set_xml SAVEMACROS 1
set_xml RECEIVERSID 1

set_pref afc_enabled 0
set_pref afconoff 0
set_pref mode_name "Cont-4/250"
set_pref wf_carrier 900

touch "$FREQS"
for entry in "3588000 USB 900 Cont-4/250" "7110000 USB 900 Cont-4/250" "14110000 USB 900 Cont-4/250"; do
    if ! grep -qF "$entry" "$FREQS"; then
        echo "$entry " >> "$FREQS"
    fi
done

echo "AmRRON Fldigi settings applied to $CFG (NBEMS/flmsg, sweet spot off, Rx ID on, AFC off, Contestia 4/250 @ 900 Hz, 80/40/20m net frequencies)."
