#!/bin/bash
# Reports the currently-selected active radio (see select-radio.sh).
ACTIVE="$HOME/radio_profiles/active-radio.conf"
if [ ! -e "$ACTIVE" ]; then
    echo "No Radio"
    exit 0
fi
source "$ACTIVE"
echo "${RIG_NAME:-Unknown}"
