#!/bin/bash
# Corrects the ADS-B Exchange feeder/site name, which the official installer
# auto-generates from your location and which is not reliably correct - it's
# come up as a different wrong value on every install so far (EE-KPNE,
# EE-DT-KPNE). If you run more than one feeder (e.g. a laptop and a desktop
# station), each one needs a distinct name - see ADSB_FEEDER_NAME in
# config.sh.example.
#
# Usage: sudo ./fix-adsb-feeder-name.sh EE-YOURNAME
set -e
NAME="${1:?Usage: $0 <feeder-name>, e.g. EE-KPHL-DESKTOP}"
sed -i "s/^USER=\".*\"/USER=\"$NAME\"/" /etc/default/adsbexchange
grep '^USER=' /etc/default/adsbexchange
systemctl restart adsbexchange-feed adsbexchange-mlat
echo "Feeder name updated and services restarted."
