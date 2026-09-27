#!/bin/bash
# What GPS does this station have right now? Answers from gpsd (the one thing that already knows every
# GPS it has attached) instead of assuming a particular puck is plugged in.
#
#   ham-gps-detect.sh                 report: the GPS sources gpsd is using (device, fix, satellites) and
#                                     every USB serial port present, classified. Never opens a serial port.
#   ham-gps-detect.sh --probe DEV     listen read-only for ~6 s on ONE port you name (e.g. /dev/ttyACM1)
#                                     and say whether it sends GPS (NMEA) sentences and whether it has a fix.
#   ham-gps-detect.sh --add DEV       ask gpsd to start using DEV (runs: sudo gpsdctl add DEV).
#
# Why it never scans blindly: opening a serial port raises its DTR/RTS lines, and on a radio or PTT
# interface that can key the transmitter. So only ports YOU name are ever opened.
#
# Sources gpsd attaches by itself once /etc/default/gpsd has USBAUTO="true": USB GPS pucks and laptop
# GPS modules it knows (u-blox, Prolific, ...; see /usr/lib/udev/rules.d/60-gpsd.rules), and - with
# udev/61-ham-gps.rules installed - the IC-705's built-in GPS. Anything else: --probe it, then --add it.
# Limitation: gpsd only feeds chrony (GPS time) for a device it opened at its own start-up by a fixed path -
# see the chrony section of Setup_Ham_Radio_Stack.sh - so a hot-plugged GPS gives position, not time sync.

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

case "$1" in
    -h|--help) usage 0 ;;
    --add)
        [ -n "$2" ] || usage 2
        echo "Asking gpsd to use $2 ..."
        sudo gpsdctl add "$2" && echo "Done. Give it ~30 s for a fix, then run this again (no arguments)."
        exit $? ;;
    --probe)
        [ -n "$2" ] || usage 2
        python3 - "$2" <<'PY'
import sys, time, serial
dev = sys.argv[1]
print(f"Listening read-only on {dev} (about 6 s per speed)...")
for baud in (4800, 9600, 38400, 115200):
    try:
        s = serial.Serial()
        s.port, s.baudrate, s.timeout = dev, baud, 1
        s.dtr = False; s.rts = False          # ask for both lines low (the kernel may still pulse them on open)
        s.open()
    except Exception as e:
        print(f"  can't open {dev}: {e}"); sys.exit(1)
    end = time.time() + 6; data = b""
    while time.time() < end:
        data += s.read(200)
    s.close()
    lines = [l.strip() for l in data.decode("latin-1").splitlines() if l.startswith("$") and "*" in l]
    if lines:
        kinds = sorted({l[3:6] for l in lines if len(l) > 6})
        print(f"  {baud} baud: {len(lines)} NMEA sentences ({', '.join(kinds)}) - this port IS a GPS.")
        fix = [l for l in lines if l[3:6] == "GGA"]
        if fix:
            q = fix[-1].split(",")
            print(f"  fix quality: {q[6] or '0'} (0 = none), satellites used: {q[7] or '0'}")
        print(f"  To use it:  ham-gps-detect.sh --add {dev}")
        sys.exit(0)
    print(f"  {baud} baud: nothing GPS-like")
print("  No GPS sentences heard. Not a GPS, wrong port, or the device's GPS output is switched off.")
PY
        exit $? ;;
    "") ;;
    *) usage 2 ;;
esac

# ---- report ------------------------------------------------------------------------------------------
echo "=== GPS sources gpsd is using"
if ! systemctl is-active --quiet gpsd.socket gpsd.service 2>/dev/null && ! pgrep -x gpsd > /dev/null; then
    echo "  gpsd is not running (sudo systemctl enable --now gpsd)."
fi
read -r -d '' REPORT_PY <<'REPORT_PY_END' || true
import sys, json
devs, best = {}, {}
for line in sys.stdin:
    try:
        m = json.loads(line)
    except ValueError:
        continue
    c = m.get("class")
    if c == "DEVICES":
        for d in m.get("devices", []):
            devs[d.get("path")] = d
    elif c == "TPV":
        best.setdefault(m.get("device", "?"), {}).update(m)
    elif c == "SKY":
        best.setdefault(m.get("device", "?"), {})["sats"] = (m.get("uSat"), len(m.get("satellites", [])))
if not devs:
    print("  none - gpsd has no GPS device attached.")
for path, d in devs.items():
    t = best.get(path, {})
    mode = t.get("mode", 0)
    fix = {0: "no data yet", 1: "no fix", 2: "2D fix", 3: "3D fix"}.get(mode, "?")
    print("  " + str(path))
    line = "     driver: %s   status: %s" % (d.get("driver", "?"), fix)
    if t.get("sats"):
        line += "   satellites used/seen: %s/%s" % t["sats"]
    print(line)
    if mode >= 2 and "lat" in t:
        print("     position: %.4f, %.4f" % (t["lat"], t["lon"]))
REPORT_PY_END
timeout 6 gpspipe -w -n 25 2> /dev/null | python3 -c "$REPORT_PY"

echo
echo "=== USB serial ports present (not opened; classified by identity only)"
GPSD_KNOWN="$(grep -o 'idVendor}=="[0-9a-f]*", ATTRS{idProduct}=="[0-9a-f]*"' /usr/lib/udev/rules.d/60-gpsd.rules 2> /dev/null | sed -E 's/.*idVendor\}=="([0-9a-f]+)".*idProduct\}=="([0-9a-f]+)"/\1:\2/')"
found=0
for p in /dev/serial/by-id/*; do
    [ -e "$p" ] || continue
    found=1
    real="$(readlink -f "$p")"
    vid="$(udevadm info -q property -n "$real" 2> /dev/null | sed -n 's/^ID_VENDOR_ID=//p')"
    pid="$(udevadm info -q property -n "$real" 2> /dev/null | sed -n 's/^ID_MODEL_ID=//p')"
    ifn="$(udevadm info -q property -n "$real" 2> /dev/null | sed -n 's/^ID_USB_INTERFACE_NUM=//p')"
    if echo "$GPSD_KNOWN" | grep -qx "$vid:$pid"; then
        why="known GPS - gpsd attaches it automatically"
    elif [ "$vid:$pid" = "0c26:0036" ] && [ "$ifn" = "02" ]; then
        if [ -f /etc/udev/rules.d/61-ham-gps.rules ]; then
            why="IC-705 built-in GPS port - gpsd attaches it (udev rule installed)"
        else
            why="IC-705 built-in GPS port - the hotplug rule is NOT installed yet (Setup_Ham_Radio_Stack.sh installs it)"
        fi
    elif [ "$vid:$pid" = "0c26:0036" ]; then
        why="IC-705 control (CI-V) port - not a GPS, leave alone"
    else
        why="unknown - could be a radio or PTT interface, so NOT opened. If you think it is a GPS: --probe $real"
    fi
    printf '  %-70s %s:%s if%s\n      -> %s\n' "$(basename "$p")" "$vid" "$pid" "${ifn:-?}" "$why"
done
[ "$found" = 0 ] && echo "  none plugged in."
exit 0
