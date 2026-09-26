#!/bin/bash
# Opens Flmsg and then Flamp alongside a Fldigi that is already starting up - in that order, each
# only after the one before it is on screen, and only once Fldigi is answering on its XML-RPC port.
# Both apps talk to Fldigi over that port and misbehave without it (Flamp in particular can't do
# anything useful, so Fldigi has to come first). Called by Start_Fldigi.sh (radio) and
# Start_Fldigi_WebSDR.sh (receive-only web-SDR copy):
#
#   open-fldigi-companions.sh radio    # Fldigi on 7362, ~/.nbems, plain "flmsg" / "flamp"
#   open-fldigi-companions.sh websdr   # Fldigi on 7363, everything under ~/Fldigi-WebSDR
#
# Already-running copies are left alone, so it is safe to call repeatedly. The two profiles never
# touch each other: each pattern below only matches its own copy.
#   - Flmsg (WebSDR) gets its Fldigi port from its own FLMSG.prefs (written by Start_Fldigi_WebSDR.sh).
#   - Flamp has --xmlrpc-server-port / --arq-server-port options but NO option for its data folder
#     (this build's --flamp-dir / --confg-dir are accepted by the help text yet make it exit at
#     once), and it keeps everything in $HOME/.nbems/FLAMP. So the WebSDR copy runs with its own
#     HOME (~/Fldigi-WebSDR/flamp-home) to keep its received files and settings apart.
# Log: <profile folder>/companions.log  (radio: ~/.nbems/companions.log)

MODE="$1"
WAIT_PORT=60      # seconds to wait for Fldigi's XML-RPC port
WAIT_WINDOW=20    # seconds to wait for each app's window before moving on anyway

case "$MODE" in
    radio)
        PORT=7362
        LOGDIR="$HOME/.nbems"
        FLMSG_MATCH="-fx"; FLMSG_PAT="flmsg"
        FLAMP_MATCH="-fx"; FLAMP_PAT="flamp"
        FLMSG_CMD=(flmsg)
        FLAMP_CMD=(flamp)
        FLAMP_HOME="$HOME"
        # Flamp's callsign: the one in the radio Fldigi's settings.
        FLAMP_CALL="$(grep -o '<MYCALL>[^<]*' "$HOME/.fldigi/fldigi_def.xml" 2> /dev/null | head -1 | sed 's/<MYCALL>//')"
        ;;
    websdr)
        PORT=7363
        WHOME="$HOME/Fldigi-WebSDR"
        LOGDIR="$WHOME"
        FLMSG_MATCH="-f"; FLMSG_PAT="^flmsg --flmsg-dir $WHOME"
        FLAMP_MATCH="-f"; FLAMP_PAT="^flamp --xmlrpc-server-port $PORT"
        # --server-port: Flmsg's forms web page starts at 8080 by default, which is Pat Winlink's.
        FLMSG_CMD=(flmsg --flmsg-dir "$WHOME/.nbems" --server-port 8280)
        FLAMP_CMD=(flamp --xmlrpc-server-port "$PORT" --arq-server-port 7323 -ti "Flamp - WEBSDR-RX")
        FLAMP_HOME="$WHOME/flamp-home"
        FLAMP_CALL="WEBSDR-RX"    # same placeholder callsign the WebSDR Fldigi uses
        ;;
    *)
        echo "usage: $0 radio|websdr" >&2
        exit 2
        ;;
esac

mkdir -p "$LOGDIR" "$FLAMP_HOME"
LOG="$LOGDIR/companions.log"
say() { echo "$1"; echo "$(date '+%F %T') $1" >> "$LOG"; }

# Flamp needs the X authority file even though its HOME is different.
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

# Wait until Fldigi actually ANSWERS on its XML-RPC port, not merely until the port is open: Flamp
# checks for Fldigi as it starts and, if it isn't there yet, shows "Start fldigi before flamp!".
fldigi_answers() {
    python3 -c 'import sys, xmlrpc.client as x; x.ServerProxy("http://127.0.0.1:%s/RPC2" % sys.argv[1]).fldigi.version()' \
        "$PORT" > /dev/null 2>&1
}
deadline=$((SECONDS + WAIT_PORT))
until fldigi_answers; do
    if [ "$SECONDS" -ge "$deadline" ]; then
        say "Fldigi never answered on XML-RPC port $PORT after ${WAIT_PORT}s - not opening Flmsg/Flamp."
        exit 1
    fi
    sleep 1
done

# start_app LABEL MATCH_FLAG PATTERN HOME_FOR_APP CMD...
start_app() {
    local label="$1" flag="$2" pat="$3" apphome="$4"; shift 4
    if pgrep "$flag" "$pat" > /dev/null; then
        say "$label: already running."
        return 0
    fi
    # Own session (setsid) so closing the launching terminal can't take it down.
    HOME="$apphome" setsid nohup "$@" > "$LOGDIR/${label,,}-companion.log" 2>&1 < /dev/null &
    local pid=$! i
    say "$label: started (pid $pid)."
    for ((i = 0; i < WAIT_WINDOW; i++)); do
        kill -0 "$pid" 2> /dev/null || { say "$label: exited early - see $LOGDIR/${label,,}-companion.log"; return 1; }
        wmctrl -lp 2> /dev/null | awk '{print $3}' | grep -qx "$pid" && return 0
        sleep 1
    done
    say "$label: no window after ${WAIT_WINDOW}s - carrying on."
}

# Flamp asks "Update Callsign and Info" at every start until it has a callsign. Fill it in - but
# only when it is empty (never overwrites one you set), and only here, while Flamp is not running
# (it rewrites its settings file when it exits).
seed_flamp_callsign() {
    local dir="$FLAMP_HOME/.nbems/FLAMP" prefs
    prefs="$dir/FLAMP.prefs"
    [ -n "$FLAMP_CALL" ] || return 0
    pgrep "$FLAMP_MATCH" "$FLAMP_PAT" > /dev/null && return 0
    mkdir -p "$dir"
    if [ ! -f "$prefs" ]; then
        # The version line matters: without it Flamp treats the file as not its own and starts blank.
        local ver
        ver="$(dpkg-query -W -f='${Version}' flamp 2> /dev/null | sed 's/-.*//')"
        printf '; FLTK preferences file format 1.0\n; vendor: w1hkj.com\n; application: FLAMP\n\n[.]\n\nversion:%s\nmycall:%s\n' \
            "${ver:-2.2.09}" "$FLAMP_CALL" > "$prefs"
    elif grep -q '^mycall:$' "$prefs"; then
        sed -i "s|^mycall:\$|mycall:$FLAMP_CALL|" "$prefs"
    fi
}
seed_flamp_callsign

start_app Flmsg "$FLMSG_MATCH" "$FLMSG_PAT" "$HOME" "${FLMSG_CMD[@]}"
start_app Flamp "$FLAMP_MATCH" "$FLAMP_PAT" "$FLAMP_HOME" "${FLAMP_CMD[@]}"
