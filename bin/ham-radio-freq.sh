#!/bin/bash
# Prints the currently active radio's frequency, checking both control paths
# this station uses: direct rigctld (Pat/WSJT-X/JS8Call) and flrig (VarAC).
# Works with whichever radio rigctld/flrig is currently pointed at.
# Prints "off" only if neither is reachable.

FREQ=$(timeout 1 rigctl -m 2 -r localhost:4532 f 2>/dev/null)
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
