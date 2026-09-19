#!/bin/bash
# Prints the currently active radio's frequency, checking both control paths
# this station uses: direct rigctld (Pat/WSJT-X/JS8Call) and flrig (VarAC).
# Works with whichever radio rigctld/flrig is currently pointed at.
# Prints "off" only if neither is reachable.
# NOTE: talks to rigctld's raw text protocol on 127.0.0.1:4532 directly
# instead of running the `rigctl` client. Every `rigctl` start sends a
# VFO A/B/A probe sequence to the radio - harmless on most rigs, but on the
# Xiegu G90 it made the radio audibly click and flip between its A and B
# VFOs every poll (every 2 seconds, from Conky).

FREQ=$(timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/4532 && printf "f\n" >&3 && read -r -t 1 -u 3 L && echo "$L"' 2>/dev/null)
case "$FREQ" in *[!0-9]*|"") FREQ="";; esac
if [ -n "$FREQ" ]; then
    awk '{printf "%.4f MHz\n", $1/1000000}' <<< "$FREQ"
    exit 0
fi

FREQ=$(timeout 1 python3 -c "
import xmlrpc.client
try:
    c = xmlrpc.client.ServerProxy('http://127.0.0.1:12345/RPC2')
    print(c.rig.get_vfo())
except Exception:
    pass
" 2>/dev/null)
if [ -n "$FREQ" ]; then
    awk '{printf "%.4f MHz\n", $1/1000000}' <<< "$FREQ"
    exit 0
fi

echo "off"
