#!/bin/bash
# Opens the real CommStat once the radio JS8Call is up - called (in the background) by Start_JS8Call.sh,
# so JS8Call and CommStat come up together the way the receive-only WebSDR pair does.
#
# Order matters: CommStat connects to JS8Call's TCP API port once, at start-up, and switches its
# connector off after 12 failed retries. So this waits until JS8Call is actually LISTENING on that
# port before it starts CommStat (never the other way round).
#
# Safe to call repeatedly: does nothing if CommStat (the real one, in ~/CommStat - not the separate
# WebSDR copy in ~/CommStat-WebSDR) is already running, or isn't installed.
# Log: ~/.cache/open-commstat.log

DIR="$HOME/CommStat"
INI="$HOME/.config/JS8Call.ini"
WAIT=120          # seconds to wait for JS8Call's port
LOG="$HOME/.cache/open-commstat.log"
mkdir -p "$(dirname "$LOG")"
say() { echo "$(date '+%F %T') $1" >> "$LOG"; }

[ -x "$DIR/linuxlauncher.sh" ] || { say "CommStat isn't installed ($DIR/linuxlauncher.sh missing) - nothing to open."; exit 0; }

PORT="$(grep -a '^TCPServerPort=' "$INI" 2> /dev/null | head -1 | cut -d= -f2)"
PORT="${PORT:-2442}"

# The real CommStat = a commstat.py / little_gucci.py process whose working directory is ~/CommStat.
commstat_running() {
    local p
    for p in $(pgrep -f 'commstat\.py|little_gucci\.py'); do
        [ "$(readlink "/proc/$p/cwd" 2> /dev/null)" = "$DIR" ] && return 0
    done
    return 1
}

if commstat_running; then
    say "CommStat is already running - leaving it alone."
    exit 0
fi

deadline=$((SECONDS + WAIT))
until ss -tln 2> /dev/null | grep -q "[:.]$PORT "; do
    if [ "$SECONDS" -ge "$deadline" ]; then
        say "JS8Call never started listening on port $PORT within ${WAIT}s - not opening CommStat."
        exit 1
    fi
    sleep 1
done

# Re-check: it may have been opened by hand while we waited.
if commstat_running; then
    say "CommStat was opened meanwhile - leaving it alone."
    exit 0
fi

# Own session (setsid) so closing the terminal that ran Start_JS8Call.sh can't take CommStat (or its
# Qt WebEngine helper processes) down with it.
setsid -f nohup "$DIR/linuxlauncher.sh" > "$HOME/.cache/commstat-radio.log" 2>&1 < /dev/null
say "JS8Call is listening on $PORT - started CommStat."
