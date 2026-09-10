#!/bin/bash
# Prints the currently active radio's mode (USB, LSB, CW, USB-D, etc.),
# checking both control paths this station uses: direct rigctld and flrig.
# Works with whichever radio rigctld/flrig is currently pointed at.
# Prints nothing if neither is reachable.

MODE=$(timeout 1 rigctl -m 2 -r localhost:4532 m 2>/dev/null | head -1)
if [ -n "$MODE" ]; then
    echo "$MODE"
    exit 0
fi

MODE=$(timeout 1 python3 -c "
import xmlrpc.client
try:
    c = xmlrpc.client.ServerProxy('http://127.0.0.1:12345/RPC2')
    print(c.rig.get_mode())
except Exception:
    pass
" 2>/dev/null)
if [ -n "$MODE" ]; then
    echo "$MODE"
fi
