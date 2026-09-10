#!/bin/bash
# Provisions a full ham radio + SDR software stack in one pass:
#   - RTL-SDR + readsb + tar1090 (ADS-B aircraft tracking, with gpsd
#     auto-detect for a USB GPS) and the official ADS-B Exchange feed client
#   - SDR++ (general-purpose SDR receiver), with helper scripts to switch
#     the RTL-SDR dongle between normal VHF/UHF/airband mode and HF/shortwave
#     direct-sampling mode (a single RTL-SDR dongle can only do one at a time)
#   - VarAC, VARA HF, VARA FM (all under Wine), Pat Winlink, JS8Call,
#     WSJT-X, and GridTracker - all sharing whichever radio is currently
#     selected via select-radio.sh (see radio_profiles/) via a single Hamlib
#     rigctld instance talking directly to its serial port. VarAC uses flrig
#     instead (see Start_VarAC.sh) since its Hamlib option doesn't work
#     under this Wine build - flrig and rigctld can't run at the same time,
#     since both want exclusive access to the one physical serial port.
#
# Assumes: this user has sudo rights, and the proprietary/Windows installers
# (VarAC, VARA HF, VARA FM, and the JS8Call/WSJT-X/GridTracker/Pat .deb
# packages) are already sitting in ~/Downloads (or wherever DOWNLOADS points
# to in config.sh) - none of those are freely redistributable, so this
# script does not fetch them for you. Everything else (rtl-sdr, readsb,
# tar1090, gpsd, SDR++, the ADS-B Exchange feed client) is downloaded
# directly from its official source.
#
# Re-run safely - most steps check before acting.
#
# NOT fully hands-off:
#   - The Wine installers (VarAC/VARA HF/VARA FM) are launched interactively
#     since their silent-install support was never verified - click through
#     each wizard once when its window appears.
#   - The ADS-B Exchange feed installer is also interactive (it uses
#     whiptail dialogs to ask for your station's lat/lon/altitude and,
#     optionally, your ADS-B Exchange account UUID).
#   - Fill in WINLINK_PASSWORD and VARA_REG_CODE in config.sh before running
#     the later sections that need them. Left blank, those sections are
#     skipped with a reminder printed at the end.
#   - IC705_SERIAL_ID is specific to one physical radio (its USB serial
#     number) - the script prints what it finds if the placeholder doesn't
#     match anything plugged in.
set -e

# ==================== CONFIGURATION ====================
# Copy config.sh.example to config.sh (in this same directory) and fill in
# your own callsign, grid square, radio serial ID, and any credentials.
# config.sh is git-ignored, so none of that ends up in version control.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "No config.sh found next to this script."
    echo "Copy config.sh.example to config.sh, edit your callsign/grid/radio serial ID/etc, and re-run."
    exit 1
fi
# ======================================================

section() { echo; echo "=== $1 ==="; }

section "System packages"
if ! dpkg --print-foreign-architectures | grep -q i386; then
    sudo dpkg --add-architecture i386
fi
sudo apt update
sudo apt install -y wine winetricks cabextract winbind libhamlib-utils curl \
    rtl-sdr gpsd gpsd-clients jq wget unzip git flrig conky-all \
    lm-sensors python3-tk pulseaudio-utils sound-theme-freedesktop \
    wmctrl x11-utils python3-serial

section "Serial port access (dialout group)"
if ! groups "$USER" | grep -qw dialout; then
    sudo usermod -aG dialout "$USER"
    echo "Added $USER to the dialout group - this only takes effect after"
    echo "you log out and back in (or reboot). Until then, rigctld/flrig"
    echo "will fail to open the IC-705 or a USB GPS with Permission denied."
else
    echo "$USER is already in the dialout group."
fi

section "RTL-SDR: blacklist the conflicting DVB-T kernel driver"
if [ ! -f /etc/modprobe.d/blacklist-rtl.conf ]; then
    echo 'blacklist dvb_usb_rtl28xxu' | sudo tee /etc/modprobe.d/blacklist-rtl.conf
    sudo rmmod dvb_usb_rtl28xxu 2>/dev/null || true
fi

section "Installing readsb (wiedehopf)"
if ! command -v readsb &>/dev/null; then
    sudo bash -c "$(wget -q -O - https://github.com/wiedehopf/adsb-scripts/raw/master/readsb-install.sh)"
else
    echo "readsb already installed."
fi

section "Installing tar1090 (wiedehopf)"
if [ ! -d /usr/share/tar1090 ]; then
    sudo bash -c "$(wget -q -O - https://github.com/wiedehopf/tar1090/raw/master/install.sh)"
else
    echo "tar1090 already installed."
fi

section "Configuring gpsd for generic USB GPS auto-detect"
sudo tee /etc/default/gpsd > /dev/null <<'EOF'
# Devices gpsd should collect to at boot time.
DEVICES=""

# Other options you want to pass to gpsd
GPSD_OPTIONS="-n -b"

# Automatically hot add/remove USB GPS devices via gpsdctl
USBAUTO="true"
EOF

section "Wiring readsb to pull live position from gpsd when a GPS is present"
if ! grep -q 'gpsd_in' /etc/default/readsb 2>/dev/null; then
    sudo sed -i 's|^NET_OPTIONS="\(.*\)"|NET_OPTIONS="\1 --net-connector=127.0.0.1,2947,gpsd_in"|' /etc/default/readsb
fi

section "Setting readsb station location"
if [ -n "$ADSB_LAT" ] && [ -n "$ADSB_LON" ]; then
    sudo sed -i -E 's/ *--lat [^ ]+ --lon [^ ]+//' /etc/default/readsb
    sudo sed -i "s|^RECEIVER_OPTIONS=\"\(.*\)\"|RECEIVER_OPTIONS=\"\1 --lat $ADSB_LAT --lon $ADSB_LON\"|" /etc/default/readsb
    echo "Location set to $ADSB_LAT, $ADSB_LON."
else
    echo "ADSB_LAT/ADSB_LON blank in config.sh - relying on GPS (if present) or no fixed location."
fi

section "Enabling readsb + gpsd"
sudo systemctl enable --now gpsd.service || true
sudo systemctl enable --now readsb.service || true

section "Installing SDR++ (nightly .deb for Ubuntu Noble base)"
if ! command -v sdrpp &>/dev/null; then
    TMP_DEB=$(mktemp --suffix=.deb)
    wget -q -O "$TMP_DEB" \
        https://github.com/AlexandreRouma/SDRPlusPlus/releases/download/nightly/sdrpp_ubuntu_noble_amd64.deb
    sudo apt-get install -y "$TMP_DEB"
    rm -f "$TMP_DEB"
else
    echo "SDR++ already installed."
fi

section "Installing SDR++ VHF/UHF <-> HF mode-switch helper scripts"
sudo mkdir -p /usr/local/bin

sudo tee /usr/local/bin/sdrpp-vhf-mode.sh > /dev/null <<'EOF'
#!/bin/bash
# Switch SDR++ to normal tuner mode (airband, VHF/UHF ham bands) and (re)launch it.
set -e
CFG="$HOME/.config/sdrpp/rtl_sdr_config.json"
pkill -x sdrpp 2>/dev/null || true
sleep 1
if systemctl is-active --quiet readsb; then
    echo "Stopping readsb so SDR++ can use the RTL-SDR dongle (sudo password may be needed)..."
    sudo systemctl stop readsb
    sleep 1
fi
if [ -f "$CFG" ]; then
    tmp=$(mktemp)
    jq '.devices |= (map_values(.directSampling = 0))' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
fi
echo "Direct sampling disabled. Launching SDR++ in normal (VHF/UHF/airband) mode..."
exec /usr/bin/sdrpp
EOF

sudo tee /usr/local/bin/sdrpp-hf-mode.sh > /dev/null <<'EOF'
#!/bin/bash
# Switch SDR++ to direct sampling mode (HF ham bands, shortwave) and (re)launch it.
# NOTE: this bypasses the tuner entirely - airband/VHF/UHF reception will NOT
# work while in this mode. Switch back with sdrpp-vhf-mode.sh when done.
set -e
CFG="$HOME/.config/sdrpp/rtl_sdr_config.json"
pkill -x sdrpp 2>/dev/null || true
sleep 1
if systemctl is-active --quiet readsb; then
    echo "Stopping readsb so SDR++ can use the RTL-SDR dongle (sudo password may be needed)..."
    sudo systemctl stop readsb
    sleep 1
fi
if [ -f "$CFG" ]; then
    tmp=$(mktemp)
    jq '.devices |= (map_values(.directSampling = 2))' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
fi
echo "Direct sampling (Q-branch) enabled. Launching SDR++ in HF mode..."
echo "Try 10.000 MHz or 15.000 MHz (WWV) in AM mode as a reference signal."
exec /usr/bin/sdrpp
EOF

sudo chmod +x /usr/local/bin/sdrpp-vhf-mode.sh /usr/local/bin/sdrpp-hf-mode.sh

section "ADS-B Exchange feed client (interactive - asks for your station info)"
echo "This installs the official ADS-B Exchange feed + MLAT client."
echo "You'll be asked for your lat/lon/altitude and, optionally, your own"
echo "ADS-B Exchange account UUID (get one at adsbexchange.com if you want"
echo "the feed tied to your account)."
read -n1 -r -p "Press any key to continue, or Ctrl+C to skip this section..."
echo
curl -L -o /tmp/axfeed.sh https://adsbexchange.com/feed.sh
sudo bash /tmp/axfeed.sh
rm -f /tmp/axfeed.sh

# The installer auto-generates a feeder/site name from your location that is
# not reliably correct - it's come up wrong with a different value on every
# install so far (EE-KPNE, EE-DT-KPNE). fix-adsb-feeder-name.sh corrects it
# to whatever ADSB_FEEDER_NAME is set to in config.sh - important to set if
# you run more than one feeder (e.g. a laptop and a desktop station both
# feeding at once), since each needs a distinct name.
cp -n "$SCRIPT_DIR/fix-adsb-feeder-name.sh" "$HOME/fix-adsb-feeder-name.sh"
chmod +x "$HOME/fix-adsb-feeder-name.sh"
if [ -n "$ADSB_FEEDER_NAME" ]; then
    if [ -f /etc/default/adsbexchange ] && ! grep -q "^USER=\"$ADSB_FEEDER_NAME\"" /etc/default/adsbexchange; then
        echo "NOTE: the ADS-B Exchange feeder name doesn't match ADSB_FEEDER_NAME"
        echo "($ADSB_FEEDER_NAME) yet - run:"
        echo "  sudo ~/fix-adsb-feeder-name.sh \"$ADSB_FEEDER_NAME\""
    fi
else
    echo "ADSB_FEEDER_NAME isn't set in config.sh, so the ADS-B Exchange feed is"
    echo "using whatever name the installer auto-generated. If you run more than"
    echo "one feeder, set ADSB_FEEDER_NAME and re-run, or fix it directly:"
    echo "  sudo ~/fix-adsb-feeder-name.sh EE-YOURNAME"
fi

section "IC-705 hardware check"
if [ ! -e "/dev/serial/by-id/$IC705_SERIAL_ID" ]; then
    echo "WARNING: /dev/serial/by-id/$IC705_SERIAL_ID not found."
    echo "Plug in the IC-705 and check the real name with:"
    echo "  ls /dev/serial/by-id/"
    echo "then update IC705_SERIAL_ID in config.sh."
else
    echo "Found: /dev/serial/by-id/$IC705_SERIAL_ID"
fi
rigctl -l 2>/dev/null | grep -i "IC-705" || echo "WARNING: Hamlib here has no IC-705 model - may need a newer Hamlib build."
rigctl -l 2>/dev/null | grep -i "FLRig" || echo "NOTE: Hamlib here has no FLRig backend (only needed if you also use flrig for VarAC)."

section "Wine prefix for VarAC / VARA HF / VARA FM"
if [ ! -d "$WINEPREFIX_HAM" ]; then
    WINEARCH=win32 WINEPREFIX="$WINEPREFIX_HAM" wineboot
fi
# Best-effort baseline for these (native, non-.NET) Windows apps under Wine.
WINEPREFIX="$WINEPREFIX_HAM" winetricks -q corefonts gdiplus vb6run pdh_nt4 win7 sound=alsa

section "Wine Mono (VarAC is a .NET application and needs this to run)"
if [ ! -d "$WINEPREFIX_HAM/drive_c/windows/mono" ]; then
    MONO_MSI=$(mktemp --suffix=.msi)
    # Older wine-mono releases (e.g. 9.4.0) hit a gpath.c assertion crash on
    # launch under Wine 9.0 - 11.3.0 is confirmed working.
    wget -q -O "$MONO_MSI" https://dl.winehq.org/wine/wine-mono/11.3.0/wine-mono-11.3.0-x86.msi
    WINEPREFIX="$WINEPREFIX_HAM" wine msiexec /i "$MONO_MSI" /qn
    rm -f "$MONO_MSI"
else
    echo "Wine Mono already installed."
fi

section "Installing VarAC, VARA HF, VARA FM (interactive - click through each wizard)"
install_wine_app() {
    local installer="$1"
    local marker="$2"  # a file/dir that exists once installed, to skip on re-run
    if [ -e "$marker" ]; then
        echo "Already installed: $marker"
        return
    fi
    if [ ! -e "$installer" ]; then
        echo "WARNING: installer not found: $installer - skipping."
        return
    fi
    echo "Launching $installer - complete the install wizard, then close it."
    WINEPREFIX="$WINEPREFIX_HAM" wine "$installer"
}
install_wine_app "$DOWNLOADS/VarAC_Installer_V15_0_18.exe" "$WINEPREFIX_HAM/drive_c/VarAC/VarAC.exe"
install_wine_app "$DOWNLOADS/VARA setup (Run as Administrator).exe" "$WINEPREFIX_HAM/drive_c/VARA/VARA.exe"
install_wine_app "$DOWNLOADS/VARA FM setup (Run as Administrator).exe" "$WINEPREFIX_HAM/drive_c/VARA FM/VARAFM.exe"

section "Configuring VARA HF (soundcard + registration)"
VARAHF_INI="$WINEPREFIX_HAM/drive_c/VARA/VARA.ini"
if [ -f "$WINEPREFIX_HAM/drive_c/VARA/VARA.exe" ] && [ ! -f "$VARAHF_INI" ]; then
    echo "First-run VARA HF to generate its config..."
    WINEPREFIX="$WINEPREFIX_HAM" AUDIODEV="$AUDIO_DEVICE" timeout 8 wine "$WINEPREFIX_HAM/drive_c/VARA/VARA.exe" || true
fi
if [ -f "$VARAHF_INI" ] && [ -n "$VARA_REG_CODE" ]; then
    sed -i \
        -e "s/^Input Device Name=.*/Input Device Name=In: USB Audio CODEC - USB Audio/" \
        -e "s/^Output Device Name=.*/Output Device Name=Out: USB Audio CODEC - USB Audi/" \
        -e "s/^Registration Code=.*/Registration Code=$VARA_REG_CODE/" \
        -e "s/^Callsign Licence 0=.*/Callsign Licence 0=$VARA_CALLSIGN_LICENSE/" \
        "$VARAHF_INI"
    echo "VARA HF configured."
else
    echo "Skipped (VARA.ini missing, or VARA_REG_CODE blank - launch VARA HF once first, or fill in the reg code)."
fi

section "Configuring VARA FM (soundcard + registration)"
if [ -f "$WINEPREFIX_HAM/drive_c/VARA FM/VARAFM.exe" ] && [ ! -f "$WINEPREFIX_HAM/drive_c/VARA FM/VARAFM.ini" ]; then
    echo "First-run VARA FM to generate its config..."
    WINEPREFIX="$WINEPREFIX_HAM" AUDIODEV="$AUDIO_DEVICE" timeout 8 wine "$WINEPREFIX_HAM/drive_c/VARA FM/VARAFM.exe" || true
fi
VARAFM_INI="$WINEPREFIX_HAM/drive_c/VARA FM/VARAFM.ini"
if [ -f "$VARAFM_INI" ] && [ -n "$VARA_REG_CODE" ]; then
    sed -i \
        -e "s/^Input Device Name=.*/Input Device Name=In: USB Audio CODEC - USB Audio/" \
        -e "s/^Output Device Name=.*/Output Device Name=Out: USB Audio CODEC - USB Audi/" \
        -e "s/^Registration Code=.*/Registration Code=$VARA_REG_CODE/" \
        -e "s/^Callsign Licence 0=.*/Callsign Licence 0=$VARA_CALLSIGN_LICENSE/" \
        "$VARAFM_INI"
    echo "VARA FM configured."
else
    echo "Skipped (VARAFM.ini missing, or VARA_REG_CODE blank)."
fi
# Note: neither VARA HF nor VARA FM actually key PTT themselves in this
# version - see Start_Pat.sh/Start_Pat_FM.sh, which use rigctld directly
# against the radio for PTT and frequency instead.

section "Configuring VarAC (rig control, identity, backup-dialog nag)"
# Same "config file doesn't exist until the app has run once" issue as VARA
# HF/FM above - force a first run to generate VarAC.ini before editing it.
if [ -f "$WINEPREFIX_HAM/drive_c/VarAC/VarAC.exe" ] && [ ! -f "$WINEPREFIX_HAM/drive_c/VarAC/VarAC.ini" ]; then
    echo "First-run VarAC to generate its config..."
    (cd "$WINEPREFIX_HAM/dosdevices/c:/VarAC" && WINARCH="win32" WINEPREFIX="$WINEPREFIX_HAM" AUDIODEV="$AUDIO_DEVICE" timeout 15 wine "$WINEPREFIX_HAM/drive_c/VarAC/VarAC.exe") || true
fi
VARAC_INI="$WINEPREFIX_HAM/drive_c/VarAC/VarAC.ini"
if [ -f "$VARAC_INI" ]; then
    sed -i \
        -e "s/^RigPTTControlType=.*/RigPTTControlType=FLRIG/" \
        -e "s/^RigFreqControlType=.*/RigFreqControlType=FLRIG/" \
        -e "s/^Mycall=.*/Mycall=$CALLSIGN/" \
        -e "s/^MyLocator=.*/MyLocator=$GRID/" \
        -e "s/^AutomaticBackup=.*/AutomaticBackup=OFF/" \
        "$VARAC_INI"
    echo "VarAC configured (rig control -> flrig, callsign/grid, backup nag silenced)."
    echo "FlrigHost/FlrigPort default to localhost:12345 in a fresh VarAC.ini,"
    echo "matching Start_Flrig_Radio.sh - left alone unless already changed."
else
    echo "Skipped (VarAC.ini still missing - VarAC's first run may need a"
    echo "display/longer timeout than this script gives it; launch it once"
    echo "yourself, close it, then re-run this script)."
fi
# VarAC has no registration-code field of its own (unlike VARA HF/FM) - it's
# free. It doesn't need an audio device set either: it drives VARA HF as its
# modem engine (see [VARAHF_CONFIG] in VarAC.ini), so VARA HF's own
# soundcard config above is what actually matters for audio.

section "VarAC launcher"
cat > "$HOME/Start_VarAC.sh" <<EOF
#!/bin/bash
# Launches flrig (via Start_Flrig_Radio.sh, so it's pre-selected for
# whichever radio is currently active via select-radio.sh, and audio gets
# synced too) followed by VarAC. VarAC's own Hamlib rig-control option
# doesn't work correctly under this Wine build (its dropdown came up with
# no selection at all), so it uses flrig instead - which means flrig and
# rigctld (used by Pat/WSJT-X/JS8Call) can never run at the same time,
# since both want exclusive access to the radio's one CAT port.
#
# Auto-stops any running rigctld below rather than refusing to launch -
# a silent refusal here is invisible (no terminal window from the Desktop
# icon), which is exactly what a plain refuse-and-exit version did before.
set -e

ACTIVE="\$HOME/radio_profiles/active-radio.conf"
if [ -e "\$ACTIVE" ]; then
    source "\$ACTIVE"
else
    AUDIO_DEVICE="$AUDIO_DEVICE"
fi

if pgrep -f "^rigctld " > /dev/null; then
    echo "Stopping rigctld so flrig can use the radio's CAT port..."
    pkill -f "^rigctld " 2>/dev/null || true
    sleep 1
fi

if ! pgrep -x "flrig" > /dev/null; then
    "\$HOME/.local/bin/Start_Flrig_Radio.sh" &
    for i in \$(seq 1 15); do
        pgrep -x "flrig" > /dev/null && break
        sleep 1
    done
    sleep 2
fi

cd "$WINEPREFIX_HAM/dosdevices/c:/VarAC"
env WINARCH="win32" WINEPREFIX="$WINEPREFIX_HAM" AUDIODEV="\$AUDIO_DEVICE" wine "$WINEPREFIX_HAM/drive_c/VarAC/VarAC.exe"
EOF
chmod +x "$HOME/Start_VarAC.sh"

# VarAC's own Windows installer drops a Desktop shortcut that launches
# VarAC.exe directly, bypassing flrig - repoint it at Start_VarAC.sh so
# flrig (needed for VarAC's PTT/CAT) comes up automatically too.
VARAC_DESKTOP="$HOME/Desktop/VarAC.desktop"
if [ -f "$VARAC_DESKTOP" ]; then
    sed -i \
        -e "s|^Exec=.*|Exec=$HOME/Start_VarAC.sh|" \
        -e "/^Path=/d" \
        "$VARAC_DESKTOP"
    echo "Repointed $VARAC_DESKTOP at Start_VarAC.sh."
fi

section "Installing JS8Call, WSJT-X, GridTracker (.deb packages)"
install_deb() {
    local pattern="$1"
    local file
    file=$(ls $pattern 2>/dev/null | head -1)
    if [ -z "$file" ]; then
        echo "WARNING: no file matching $pattern in $DOWNLOADS - skipping."
        return
    fi
    echo "Installing $file..."
    sudo apt install -y "$file"
}
install_deb "$DOWNLOADS/js8call*.deb"
install_deb "$DOWNLOADS/wsjtx*.deb"
install_deb "$DOWNLOADS/GridTracker2*.deb"

section "Installing Pat Winlink (.deb package)"
install_deb "$DOWNLOADS/pat_*.deb"

section "rigctld direct-to-radio bridge + Pat config"
mkdir -p "$HOME/.config/pat"
# Written directly rather than via `pat configure`/`pat init`, both of which
# expect an interactive terminal (an editor, or prompts) and would hang here.
python3 - "$CALLSIGN" "$GRID" "$WINLINK_PASSWORD" "$IC705_SERIAL_ID" <<'PYEOF'
import json, sys, os
callsign, grid, password, serial_id = sys.argv[1:5]
path = os.path.expanduser("~/.config/pat/config.json")
if os.path.exists(path):
    with open(path) as f:
        cfg = json.load(f)
else:
    cfg = {
        "auxiliary_addresses": [],
        "auto_download_size_limit": -1,
        "service_codes": ["PUBLIC"],
        "http_addr": "localhost:8080",
        "motd": ["Open source Winlink client - getpat.io"],
        "connect_aliases": {
            "telnet": "telnet://{mycall}:CMSTelnet@cms.winlink.org:8772/wl2k"
        },
        "listen": [],
    }
cfg["mycall"] = callsign
cfg["locator"] = grid
if password:
    cfg["secure_login_password"] = password
cfg.setdefault("hamlib_rigs", {})["ic705"] = {"address": "localhost:4532", "network": "tcp"}
cfg["varahf"] = {"addr": "127.0.0.1:8300", "rig": "ic705", "ptt_ctrl": True}
cfg["varafm"] = {"addr": "127.0.0.1:8300", "rig": "ic705", "ptt_ctrl": True}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
print(f"Wrote {path}")
PYEOF

section "Radio profiles + active-radio picker"
# Multi-radio support: each radio this station uses gets a profile in
# ~/radio_profiles/<name>.conf (plain KEY="value" bash, sourced directly -
# see radio_profiles/*.conf in this repo for real, working examples: IC-705,
# FT-891, TX-500 MP, and Xiegu G-90). select-radio.sh lets you explicitly
# pick which one is "active" (a symlink at radio_profiles/active-radio.conf)
# rather than auto-detecting from what's plugged in - auto-detection breaks
# the moment two radios are connected at once, which is exactly what
# happened during development. Start_Flrig_Radio.sh, sync-radio-audio.sh,
# Start_Pat.sh, and Start_Pat_FM.sh all just read that one active-radio.conf
# symlink; nothing else needs to change when you add a radio.
#
# This design is inspired by EmComm Tools OS's own radio/mode selectors
# (community.emcommtools.com) - its et-radio (explicit radio picker) and
# et-mode (explicit workflow picker) patterns are the reason this uses an
# explicit picker instead of auto-detection.
mkdir -p "$HOME/radio_profiles/audio" "$HOME/.local/bin"
cp "$SCRIPT_DIR/bin/"*.sh "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/select-radio.sh" "$HOME/.local/bin/ham-radio-name.sh" \
    "$HOME/.local/bin/Start_Flrig_Radio.sh" "$HOME/.local/bin/sync-radio-audio.sh" \
    "$HOME/.local/bin/ham-radio-freq.sh" "$HOME/.local/bin/ham-radio-mode.sh" \
    "$HOME/.local/bin/ham-gps-grid.sh"
if [ -d "$SCRIPT_DIR/radio_profiles" ]; then
    cp -n "$SCRIPT_DIR/radio_profiles/"*.conf "$HOME/radio_profiles/" 2>/dev/null || true
    cp -n "$SCRIPT_DIR/radio_profiles/audio/"*.sh "$HOME/radio_profiles/audio/" 2>/dev/null || true
    chmod +x "$HOME/radio_profiles/audio/"*.sh 2>/dev/null || true
fi
echo "Installed select-radio.sh, ham-radio-name.sh, Start_Flrig_Radio.sh,"
echo "sync-radio-audio.sh to ~/.local/bin, and any radio profiles not already"
echo "present to ~/radio_profiles (existing ones were left untouched)."
echo "Run select-radio.sh to choose the active radio before using any of the"
echo "apps below - if none is chosen yet, this falls back to the IC-705"
echo "config from config.sh."

mkdir -p "$HOME/Desktop"
cat > "$HOME/Desktop/Select Radio.desktop" <<'EOF'
[Desktop Entry]
Name=Select Radio
Comment=Choose which radio is active (used by flrig, Pat, and the audio sync)
Exec=bash -c "$HOME/.local/bin/select-radio.sh; echo; read -p 'Press Enter to close...'"
Type=Application
Terminal=true
Icon=radio
Categories=HamRadio;
EOF
chmod +x "$HOME/Desktop/Select Radio.desktop"
gio set "$HOME/Desktop/Select Radio.desktop" "metadata::trusted" true 2>/dev/null || true
echo "Select Radio.desktop written - without this shortcut, switching radios"
echo "means remembering to run select-radio.sh by hand every time."

section "Start_Pat.sh / Start_Pat_FM.sh"
# Both scripts drive whichever radio is currently selected via
# select-radio.sh (~/radio_profiles/active-radio.conf) - no flrig in this
# path at all (flrig is unstable and unnecessary here; it's only used
# separately for VarAC via Start_VarAC.sh, which can't run at the same time
# as this - both want exclusive access to the same physical serial port).
# If no radio has been selected yet, falls back to the IC-705 from
# config.sh so a fresh setup still works before you've run select-radio.sh.
cat > "$HOME/Start_Pat.sh" <<EOF
#!/bin/bash
set -e

ACTIVE="\$HOME/radio_profiles/active-radio.conf"
if [ -e "\$ACTIVE" ]; then
    source "\$ACTIVE"
else
    RIG_MODEL=3085
    RIG_NAME="IC-705"
    SERIAL_DEVICE="/dev/serial/by-id/$IC705_SERIAL_ID"
    BAUD_RATE=115200
    AUDIO_DEVICE="$AUDIO_DEVICE"
fi

for var in RIG_MODEL RIG_NAME SERIAL_DEVICE BAUD_RATE AUDIO_DEVICE; do
    val="\${!var}"
    if [ -z "\$val" ] || [[ "\$val" == *CHANGE_ME* ]]; then
        echo "ERROR: active radio (\$RIG_NAME) still has a placeholder for \$var - fill it in first."
        exit 1
    fi
done
if [ ! -e "\$SERIAL_DEVICE" ]; then
    echo "ERROR: \$RIG_NAME's serial device (\$SERIAL_DEVICE) doesn't exist. Is it plugged in?"
    exit 1
fi

rigctld_responsive() {
    timeout 3 rigctl -m 2 -r localhost:4532 f > /dev/null 2>&1
}

CHAIN_RESTARTED=0
if ! rigctld_responsive; then
    CHAIN_RESTARTED=1
    pkill -f "^rigctld " 2>/dev/null || true
    sleep 1
    PTT_ARGS=()
    [ -n "\$PTT_TYPE" ] && PTT_ARGS=(-P "\$PTT_TYPE")
    rigctld -m "\$RIG_MODEL" -r "\$SERIAL_DEVICE" -s "\$BAUD_RATE" "\${PTT_ARGS[@]}" -t 4532 &
    for i in \$(seq 1 10); do
        rigctld_responsive && break
        sleep 1
    done
    if ! rigctld_responsive; then
        echo "ERROR: rigctld didn't come up talking to \$RIG_NAME."
        echo "Double check SERIAL_DEVICE/BAUD_RATE in \$ACTIVE against the radio."
        exit 1
    fi
fi

# Pat Winlink HF needs the radio in USB-D (PKTUSB), not whatever mode it was
# last left in by another app. Timeout-wrapped like every other rigctl call
# here - a wedged rigctld (seen once: still listening on 4532 but not
# actually answering, needing a kill+restart to clear) would otherwise hang
# this indefinitely with no way to recover short of killing the script.
timeout 5 rigctl -m 2 -r localhost:4532 M PKTUSB 2400 > /dev/null 2>&1 || true

if pgrep -f "VARAFM.exe" > /dev/null; then
    pkill -f "VARAFM.exe"
    sleep 2
fi
if ! pgrep -f "VARA.exe" > /dev/null; then
    env WINEPREFIX="$WINEPREFIX_HAM" AUDIODEV="\$AUDIO_DEVICE" wine "$WINEPREFIX_HAM/drive_c/VARA/VARA.exe" &
    for i in \$(seq 1 30); do
        (exec 3<>/dev/tcp/127.0.0.1/8300) 2>/dev/null && exec 3>&- && break
        sleep 1
    done
fi

if pgrep -f "pat http" > /dev/null; then
    if [ "\$CHAIN_RESTARTED" = "1" ]; then
        pkill -f "pat http" 2>/dev/null
        sleep 1
    else
        xdg-open http://localhost:8080 2>/dev/null &
        exit 0
    fi
fi
pat http &
PAT_PID=\$!
for i in \$(seq 1 20); do
    (exec 3<>/dev/tcp/127.0.0.1/8080) 2>/dev/null && exec 3>&- && break
    sleep 1
done
xdg-open http://localhost:8080 2>/dev/null &
wait "\$PAT_PID"
EOF
chmod +x "$HOME/Start_Pat.sh"

cat > "$HOME/Start_Pat_FM.sh" <<EOF
#!/bin/bash
set -e

ACTIVE="\$HOME/radio_profiles/active-radio.conf"
if [ -e "\$ACTIVE" ]; then
    source "\$ACTIVE"
else
    RIG_MODEL=3085
    RIG_NAME="IC-705"
    SERIAL_DEVICE="/dev/serial/by-id/$IC705_SERIAL_ID"
    BAUD_RATE=115200
    AUDIO_DEVICE="$AUDIO_DEVICE"
fi

for var in RIG_MODEL RIG_NAME SERIAL_DEVICE BAUD_RATE AUDIO_DEVICE; do
    val="\${!var}"
    if [ -z "\$val" ] || [[ "\$val" == *CHANGE_ME* ]]; then
        echo "ERROR: active radio (\$RIG_NAME) still has a placeholder for \$var - fill it in first."
        exit 1
    fi
done
if [ ! -e "\$SERIAL_DEVICE" ]; then
    echo "ERROR: \$RIG_NAME's serial device (\$SERIAL_DEVICE) doesn't exist. Is it plugged in?"
    exit 1
fi

rigctld_responsive() {
    timeout 3 rigctl -m 2 -r localhost:4532 f > /dev/null 2>&1
}

CHAIN_RESTARTED=0
if ! rigctld_responsive; then
    CHAIN_RESTARTED=1
    pkill -f "^rigctld " 2>/dev/null || true
    sleep 1
    PTT_ARGS=()
    [ -n "\$PTT_TYPE" ] && PTT_ARGS=(-P "\$PTT_TYPE")
    rigctld -m "\$RIG_MODEL" -r "\$SERIAL_DEVICE" -s "\$BAUD_RATE" "\${PTT_ARGS[@]}" -t 4532 &
    for i in \$(seq 1 10); do
        rigctld_responsive && break
        sleep 1
    done
    if ! rigctld_responsive; then
        echo "ERROR: rigctld didn't come up talking to \$RIG_NAME."
        echo "Double check SERIAL_DEVICE/BAUD_RATE in \$ACTIVE against the radio."
        exit 1
    fi
fi

# Pat Winlink FM needs the radio in actual FM mode, not USB-D -- FM digital
# packet uses real FM modulation, unlike HF data modes. Timeout-wrapped for
# the same reason as the HF version above - a wedged rigctld shouldn't hang
# this indefinitely.
timeout 5 rigctl -m 2 -r localhost:4532 M FM 0 > /dev/null 2>&1 || true

if pgrep -f "VARA.exe" > /dev/null; then
    pkill -f "VARA.exe"
    sleep 2
fi
if ! pgrep -f "VARAFM.exe" > /dev/null; then
    env WINEPREFIX="$WINEPREFIX_HAM" AUDIODEV="\$AUDIO_DEVICE" wine "$WINEPREFIX_HAM/drive_c/VARA FM/VARAFM.exe" &
    for i in \$(seq 1 30); do
        (exec 3<>/dev/tcp/127.0.0.1/8300) 2>/dev/null && exec 3>&- && break
        sleep 1
    done
fi

if pgrep -f "pat http" > /dev/null; then
    if [ "\$CHAIN_RESTARTED" = "1" ]; then
        pkill -f "pat http" 2>/dev/null
        sleep 1
    else
        xdg-open http://localhost:8080 2>/dev/null &
        exit 0
    fi
fi
pat http &
PAT_PID=\$!
for i in \$(seq 1 20); do
    (exec 3<>/dev/tcp/127.0.0.1/8080) 2>/dev/null && exec 3>&- && break
    sleep 1
done
xdg-open http://localhost:8080 2>/dev/null &
wait "\$PAT_PID"
EOF
chmod +x "$HOME/Start_Pat_FM.sh"
echo "Start_Pat.sh and Start_Pat_FM.sh written (radio-agnostic via active-radio.conf)."

section "stop-pat.sh"
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/stop-pat.sh" <<'EOF'
#!/bin/bash
# Stops Pat Winlink and whichever VARA engine it started (HF or FM), so
# Conky reflects reality and the radio's shared serial/audio path is free
# for the next thing (VarAC, WSJT-X, JS8Call, etc.).
found=0

for pattern in "pat http" "VARA.exe" "VARAFM.exe"; do
    pids=$(pgrep -f "$pattern")
    if [ -n "$pids" ]; then
        echo "Stopping: $pattern ($pids)"
        pkill -f "$pattern"
        found=1
    fi
done

if [ "$found" = "0" ]; then
    echo "Nothing to stop -- Pat Winlink and VARA HF/FM are not running."
else
    sleep 1
    echo "Done."
fi
EOF
chmod +x "$HOME/.local/bin/stop-pat.sh"

mkdir -p "$HOME/Desktop"
cat > "$HOME/Desktop/Stop Pat Winlink.desktop" <<EOF
[Desktop Entry]
Name=Stop Pat Winlink
Comment=Stop Pat Winlink and its VARA HF/FM engine
Exec=bash -c "\$HOME/.local/bin/stop-pat.sh; echo; read -p 'Press Enter to close...'"
Type=Application
Terminal=true
Icon=process-stop
Categories=HamRadio;
EOF
chmod +x "$HOME/Desktop/Stop Pat Winlink.desktop"
echo "stop-pat.sh and its Desktop shortcut written."

section "GridTracker <-> JS8Call UDP alignment"
JS8_INI="$HOME/.config/JS8Call.ini"
if [ -f "$JS8_INI" ]; then
    sed -i \
        -e "s/^UDPEnabled=.*/UDPEnabled=true/" \
        -e "s/^UDPServerPort=.*/UDPServerPort=2237/" \
        "$JS8_INI"
    echo "JS8Call UDP reporting enabled on port 2237 (matches WSJT-X/GridTracker default)."
else
    echo "JS8Call.ini not found yet - run JS8Call once first, then re-run this section."
fi
echo "In WSJT-X and JS8Call, set Settings -> Radio -> Rig: 'Hamlib NET rigctl',"
echo "Network Server: 127.0.0.1:4532, PTT Method: CAT. GridTracker needs no"
echo "changes - it already listens on UDP 2237 by default."

section "Conky station-status monitor + 10-minute ID timer"
# These were originally hand-built directly on a live machine and never
# ported into this script - every fresh install skipped them silently,
# which is exactly the gap that was found and fixed here. conky.conf and
# id-timer.py are tracked in this repo (conky/) since their content isn't
# generated from config.sh; only copied into place (not overwritten, so
# any hand-tuning survives a re-run).
mkdir -p "$HOME/.config/conky" "$HOME/.config/autostart" "$HOME/.local/bin"
cp -n "$SCRIPT_DIR/conky/conky.conf" "$HOME/.config/conky/conky.conf"
# The repo's copy uses the placeholder callsign N0CALL (same convention as
# config.sh.example) so nobody's real callsign sits in version control -
# swap in the real one now. A no-op on re-run once it's already been swapped.
sed -i "s/N0CALL/$CALLSIGN/" "$HOME/.config/conky/conky.conf"
cp -n "$SCRIPT_DIR/conky/id-timer.py" "$HOME/.local/bin/id-timer.py"
chmod +x "$HOME/.local/bin/id-timer.py"

cat > "$HOME/.config/autostart/conky.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Conky (Ham Radio Status)
Exec=conky -c $HOME/.config/conky/conky.conf
X-GNOME-Autostart-enabled=true
Terminal=false
EOF

cat > "$HOME/.config/autostart/id-timer.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=ID Timer
Exec=python3 $HOME/.local/bin/id-timer.py
X-GNOME-Autostart-enabled=true
Terminal=false
EOF
echo "Conky and the ID timer are installed and will autostart on next login"
echo "(or start them now: conky -c ~/.config/conky/conky.conf &, python3 ~/.local/bin/id-timer.py &)."

section "Desktop shortcuts"
mkdir -p "$HOME/Desktop"

cat > "$HOME/Desktop/tar1090.desktop" <<'EOF'
[Desktop Entry]
Name=ADS-B Map (tar1090)
Comment=Live aircraft tracking map from readsb/RTL-SDR
Exec=xdg-open http://localhost/tar1090/
Type=Application
Terminal=false
StartupNotify=true
Icon=x-plane
Categories=Network;
EOF

cat > "$HOME/Desktop/readsb-start.desktop" <<'EOF'
[Desktop Entry]
Name=Start readsb
Comment=Start the readsb ADS-B decoder
Exec=bash -c 'sudo systemctl start readsb; echo; sudo systemctl status readsb --no-pager -l; read -n1 -r -p "Press any key to close..."'
Type=Application
Terminal=true
StartupNotify=true
Icon=media-playback-start
Categories=System;
EOF

cat > "$HOME/Desktop/readsb-stop.desktop" <<'EOF'
[Desktop Entry]
Name=Stop readsb
Comment=Stop the readsb ADS-B decoder to free the RTL-SDR dongle for other apps (e.g. SDR++)
Exec=bash -c 'sudo systemctl stop readsb; echo; sudo systemctl status readsb --no-pager -l; read -n1 -r -p "Press any key to close..."'
Type=Application
Terminal=true
StartupNotify=true
Icon=media-playback-stop
Categories=System;
EOF

cat > "$HOME/Desktop/sdrpp-vhf.desktop" <<'EOF'
[Desktop Entry]
Encoding=UTF-8
Version=1.0
Type=Application
Terminal=true
Exec=bash -c '/usr/local/bin/sdrpp-vhf-mode.sh; read -n1 -r -p "Press any key to close this window..."'
Name=SDR++ (Airband/VHF/UHF)
Comment=Normal tuner mode: aircraft AM, 6m/2m/70cm ham bands
Icon=/usr/share/sdrpp/icons/sdrpp.png
Categories=HamRadio
EOF

cat > "$HOME/Desktop/sdrpp-hf.desktop" <<'EOF'
[Desktop Entry]
Encoding=UTF-8
Version=1.0
Type=Application
Terminal=true
Exec=bash -c '/usr/local/bin/sdrpp-hf-mode.sh; read -n1 -r -p "Press any key to close this window..."'
Name=SDR++ (HF/Shortwave)
Comment=Direct sampling mode: ham HF bands, shortwave broadcast (disables airband/VHF/UHF while active)
Icon=/usr/share/sdrpp/icons/sdrpp.png
Categories=HamRadio
EOF

cat > "$HOME/Desktop/Pat Winlink (HF).desktop" <<EOF
[Desktop Entry]
Name=Pat Winlink (HF)
Exec=$HOME/Start_Pat.sh
Type=Application
StartupNotify=true
Icon=mail-send-receive
Terminal=false
EOF

if [ -f "$HOME/Start_Pat_FM.sh" ]; then
cat > "$HOME/Desktop/Pat Winlink (FM).desktop" <<EOF
[Desktop Entry]
Name=Pat Winlink (FM)
Exec=$HOME/Start_Pat_FM.sh
Type=Application
StartupNotify=true
Icon=mail-send-receive
Terminal=false
EOF
fi

if [ -f "$SCRIPT_DIR/ic705-channel-tools/ic705-channel-picker.py" ]; then
    if [ ! -f "$SCRIPT_DIR/ic705-channel-tools/ic705_channels.json" ]; then
        echo "Building the IC-705 channel index from the tracked CSVs..."
        (cd "$SCRIPT_DIR/ic705-channel-tools" && python3 build_channel_index.py) || \
            echo "WARNING: build_channel_index.py failed - see ic705-channel-tools/README.md."
    fi
cat > "$HOME/Desktop/IC-705 Channel Picker.desktop" <<EOF
[Desktop Entry]
Name=IC-705 Channel Picker
Comment=Browse programmed memory channels by name/group and jump to one
Exec=python3 "$SCRIPT_DIR/ic705-channel-tools/ic705-channel-picker.py"
Type=Application
StartupNotify=true
Icon=radio
Terminal=false
Categories=HamRadio;
EOF
fi

chmod +x "$HOME/Desktop/"*.desktop
for f in "$HOME/Desktop/"*.desktop; do gio set "$f" "metadata::trusted" true 2>/dev/null || true; done

section "Done"
echo "Reminders:"
[ -z "$WINLINK_PASSWORD" ] && echo "  - WINLINK_PASSWORD was blank, edit ~/.config/pat/config.json manually."
[ -z "$VARA_REG_CODE" ] && echo "  - VARA_REG_CODE was blank, VARA HF/FM are unregistered until you enter it in each app."
[ -z "$ADSB_LAT" ] && echo "  - ADSB_LAT/ADSB_LON were blank, readsb has no fixed location unless a GPS is plugged in."
echo "  - Verify Start_Pat_FM.sh looks correct (see note above) before using the FM shortcut."
echo "  - Only one of {VarAC, Pat Winlink HF, Pat Winlink FM, WSJT-X, JS8Call} at a time - they all share the one radio."
echo "  - Run ~/.local/bin/select-radio.sh to choose which radio is active before"
echo "    using any of the above - see radio_profiles/*.conf in this repo for"
echo "    real examples (IC-705, FT-891, TX-500 MP, Xiegu G-90)."
echo "  - The RTL-SDR dongle is also one-at-a-time: readsb (ADS-B) and SDR++"
echo "    can't use it simultaneously. Use the readsb start/stop shortcuts to free it."
echo "  - SDR++'s VHF/UHF and HF/Shortwave modes are also one-at-a-time on a single dongle."
