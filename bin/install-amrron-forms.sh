#!/bin/bash
# Installs the bundled AmRRON custom HTML forms (amrron-forms/ in the repo,
# deployed by the setup script to ~/.local/share/amrron-forms/) into an
# Flmsg data folder's CUSTOM directory, where Flmsg looks for custom forms.
# Never overwrites a file that's already there, so nothing you changed or
# added is touched. Safe to run on every launch.
#
# Usage: install-amrron-forms.sh [flmsg-dir]     (default ~/.nbems)
#   real Flmsg:       ~/.nbems            (Start_Fldigi.sh / Start_Flmsg.sh)
#   WebSDR Flmsg:     ~/Fldigi-WebSDR/.nbems   (Start_Fldigi_WebSDR.sh)
set -e

DEST="${1:-$HOME/.nbems}/CUSTOM"
SRC="$HOME/.local/share/amrron-forms"
[ -d "$SRC" ] || SRC="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)/amrron-forms"
if [ ! -d "$SRC" ]; then
    echo "AmRRON forms bundle not found - skipping."
    exit 0
fi

mkdir -p "$DEST"
added=0
for f in "$SRC"/*.html; do
    [ -e "$f" ] || continue
    if [ ! -e "$DEST/$(basename "$f")" ]; then
        cp "$f" "$DEST/"
        added=$((added + 1))
    fi
done
[ "$added" -gt 0 ] && echo "AmRRON forms: installed $added file(s) into $DEST"
exit 0
