#!/bin/bash
# Prints the current Maidenhead grid square from a live GPS fix via gpsd,
# or "No GPS fix" if gpsd has no USB GPS plugged in / no fix yet.
timeout 3 gpspipe -w -n 8 2>/dev/null | python3 -c '
import sys, json

lat = lon = None
for line in sys.stdin:
    try:
        msg = json.loads(line)
    except ValueError:
        continue
    if msg.get("class") == "TPV" and "lat" in msg and "lon" in msg:
        lat, lon = msg["lat"], msg["lon"]

if lat is None:
    print("No GPS fix")
    sys.exit(0)

A = ord("A")
la, lo = lat + 90, lon + 180
field_lon = chr(A + int(lo / 20))
field_lat = chr(A + int(la / 10))
lo %= 20
la %= 10
square_lon = int(lo / 2)
square_lat = int(la)
lo = (lo % 2) * 12
la = (la % 1) * 24
subsq_lon = chr(A + int(lo)).lower()
subsq_lat = chr(A + int(la)).lower()
print(f"{field_lon}{field_lat}{square_lon}{square_lat}{subsq_lon}{subsq_lat}")
'
