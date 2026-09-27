#!/bin/bash
# Prints the station's Maidenhead grid square and where it came from, for the Conky GPS row:
#   FN20ta (IC-705)    live fix from whichever GPS gpsd is using (name taken from the device: IC-705,
#   FN20ta (u-blox)    u-blox puck or laptop module, or just "GPS" for anything else)
#   FN20ta (fixed)     no live fix, but a fixed station location is known (~/.config/wxstation/config,
#                      which the setup script fills in from ADSB_LAT / ADSB_LON in config.sh)
#   No fix (IC-705)    a GPS is attached but has no fix yet (indoors, just plugged in) and no fixed location
#   No GPS             nothing attached and no fixed location
# See bin/ham-gps-detect.sh for what gpsd currently sees.
#
#   ham-gps-grid.sh            just the grid text above
#   ham-gps-grid.sh --conky    Conky markup for TWO rows from one gpsd read (for ${execpi ...}):
#                                GPS Grid   FN20mb (IC-705)
#                                Position   40.0637, -74.9867   (decimal degrees; dimmed when this is the
#                                                                fixed location rather than a live fix)
timeout 3 gpspipe -w -n 14 2>/dev/null | python3 -c '
import sys, json, os

MODE = sys.argv[1] if len(sys.argv) > 1 else ""
lat = lon = None
dev = None       # device that gave the fix
seen = None      # any device gpsd reports at all
for line in sys.stdin:
    try:
        msg = json.loads(line)
    except ValueError:
        continue
    c = msg.get("class")
    if c == "DEVICES" and msg.get("devices"):
        seen = msg["devices"][0].get("path")
    elif c == "TPV":
        seen = msg.get("device", seen)
        if msg.get("mode", 0) >= 2 and "lat" in msg and "lon" in msg:
            lat, lon, dev = msg["lat"], msg["lon"], msg.get("device")

def name(path):
    # gpsd often reports a bare /dev/ttyACMx; recover the descriptive name from /dev/serial/by-id.
    import glob
    real = os.path.realpath(path) if path else ""
    label = path or ""
    for link in glob.glob("/dev/serial/by-id/*") + glob.glob("/dev/gps-*"):
        if os.path.realpath(link) == real:
            label = link
            break
    p = label.lower()
    if "ic-705" in p or "icom" in p or "gps-ic705" in p:
        return "IC-705"
    if "u-blox" in p or "ublox" in p:
        return "u-blox"
    return "GPS"

def grid(la, lo):
    A = ord("A")
    la, lo = la + 90, lo + 180
    fl, fa = chr(A + int(lo / 20)), chr(A + int(la / 10))
    lo %= 20; la %= 10
    sl, sa = int(lo / 2), int(la)
    lo = (lo % 2) * 12; la = (la % 1) * 24
    return "%s%s%d%d%s%s" % (fl, fa, sl, sa, chr(A + int(lo)).lower(), chr(A + int(la)).lower())

live = lat is not None
label = None
if live:
    label = "%s (%s)" % (grid(lat, lon), name(dev))
else:
    # No live fix: fall back to the fixed station location, if there is one.
    try:
        cfg = dict(l.strip().split("=", 1) for l in open(os.path.expanduser("~/.config/wxstation/config"))
                   if "=" in l and not l.startswith("#"))
        lat, lon = float(cfg["LAT"]), float(cfg["LON"])
        label = "%s (fixed)" % grid(lat, lon)
    except (OSError, KeyError, ValueError):
        lat = lon = None
        label = "No fix (%s)" % name(seen) if seen else "No GPS"

if MODE == "--conky":
    print("${color b8bcc8}GPS Grid${goto 110}${color 61afef}%s" % label)
    if lat is not None:
        colour = "61afef" if live else "5c6370"          # blue = live fix, dim = fixed location
        print("${color b8bcc8}Position${goto 110}${color %s}%.4f, %.4f" % (colour, lat, lon))
else:
    print(label)
' "$1"
