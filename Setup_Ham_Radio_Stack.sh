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
    rtl-sdr gpsd gpsd-clients jq wget unzip git flrig

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
pkill -f "^/usr/bin/sdrpp" 2>/dev/null || true
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
pkill -f "^/usr/bin/sdrpp" 2>/dev/null || true
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

section "VarAC launcher"
cat > "$HOME/Start_VarAC.sh" <<EOF
#!/bin/bash
# Ensure FLRIG is running first
if ! pgrep -x "flrig" > /dev/null; then
    flrig &
    sleep 3
fi
# Launch the VarAC + VARA HF Wine stack with direct radio audio mapping
env WINARCH="win32" WINEPREFIX="$WINEPREFIX_HAM" AUDIODEV="$AUDIO_DEVICE" wine "$WINEPREFIX_HAM/drive_c/VarAC/VarAC.exe"
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
    "$HOME/.local/bin/Start_Flrig_Radio.sh" "$HOME/.local/bin/sync-radio-audio.sh"
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
# last left in by another app.
rigctl -m 2 -r localhost:4532 M PKTUSB 2400 > /dev/null 2>&1

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
# packet uses real FM modulation, unlike HF data modes.
rigctl -m 2 -r localhost:4532 M FM 0 > /dev/null 2>&1

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
