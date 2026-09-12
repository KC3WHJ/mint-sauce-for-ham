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
#   - chrony, using the USB GPS as a time source (alongside normal NTP) -
#     accurate time with no internet dependency, for off-grid use.
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
    rtl-sdr gpsd gpsd-clients chrony jq wget unzip git flrig conky-all \
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

section "Configuring chrony to use the GPS for time sync"
# FT8 only needs ~0.5s accuracy, already met by plain internet NTP - the
# real value of GPS timing here is accurate time with ZERO internet
# dependency (useful for this station's off-grid/emergency-comms angle,
# e.g. AmRRON). gpsd's SHM interface looks like the obvious choice but its
# SHM units 0/1 are permanently root-only by design, and gpsd's privilege
# drop at startup (it briefly runs as root to open the device, then drops
# to an unprivileged "gpsd" user) means it never populates the
# unprivileged-accessible units 2/3 either - chronyd (which also drops
# root) can never read either pair. chrony's own FAQ recommends its newer
# SOCK interface instead, which sidesteps this entirely - but it needs the
# exact NMEA-only ("clock", not PPS - this is a plain USB GPS puck with no
# PPS output) socket naming convention gpsd 3.25+ introduced (.clk.
# infix), named after the literal device path string gpsd's own udev
# integration passes it (the raw tty name, e.g. ttyACM0 - NOT a by-id
# path, confirmed by reading gpsd's shipped udev rule + systemd unit
# directly); gpsd must start AFTER chronyd creates the socket, the reverse
# of normal boot order; and Ubuntu's shipped gpsd AppArmor profile has no
# rule at all for this modern socket naming, silently blocking every write
# regardless of correct file permissions. All of these were found and
# fixed live on a real machine 2026-09-11/12 - see the "Hard-won lessons"
# section of README.md for the full diagnostic trail if this needs
# revisiting.
sudo systemctl disable --now systemd-timesyncd 2>/dev/null || true

GPS_BY_ID=$(ls /dev/serial/by-id/ 2>/dev/null | grep -i gps | head -1)
if [ -n "$GPS_BY_ID" ]; then
    # The socket's name is whatever literal device path string gpsd was
    # told to open the device with - confirmed via gpsd's own `-D 5` debug
    # output. A by-id path was tried first (reasoning: it's the stable
    # identifier, surely that's what gpsd's own udev integration uses) and
    # genuinely worked in manual testing - but manual testing was
    # seeding gpsd with that exact by-id path as an argument, which begs
    # the question. gpsd's REAL automatic attachment path is the
    # gpsd-shipped udev rule (/usr/lib/udev/rules.d/60-gpsd.rules) feeding
    # a systemd template unit, gpsdctl@%k.service - %k is the KERNEL
    # device name, and its ExecStart is literally
    # `gpsdctl add /dev/%I`. That is always the raw tty name (e.g.
    # ttyACM0), never a by-id path, confirmed 2026-09-12 by reading that
    # unit directly. The tty name is what this needs to match.
    GPS_TTY=$(basename "$(readlink -f "/dev/serial/by-id/$GPS_BY_ID")")
    REFCLOCK_LINE="refclock SOCK /run/chrony.clk.${GPS_TTY}.sock refid GPS precision 1e-1 offset 0.9999"
    if ! grep -q "^refclock SOCK .*${GPS_TTY}" /etc/chrony/chrony.conf 2>/dev/null; then
        # Remove any older refclock line (e.g. from a previous run against
        # a different GPS, or an older version of this script's incorrect
        # by-id-based naming) before adding the current correct one.
        sudo sed -i '/^refclock SOCK .*\.clk\./d' /etc/chrony/chrony.conf
        echo "" | sudo tee -a /etc/chrony/chrony.conf > /dev/null
        echo "# GPS time via gpsd's SOCK interface - added by Setup_Ham_Radio_Stack.sh" | sudo tee -a /etc/chrony/chrony.conf > /dev/null
        echo "$REFCLOCK_LINE" | sudo tee -a /etc/chrony/chrony.conf > /dev/null
        echo "Added GPS refclock ($GPS_TTY) to chrony.conf."
    else
        echo "GPS refclock already configured for $GPS_TTY."
    fi

    # After=/Wants= alone only guarantees chrony.service's own start job
    # finishes first - for a Type=forking service that just means "the
    # forking parent process exited," not "chrony has actually created
    # the refclock socket file yet." Confirmed via a real reboot
    # 2026-09-12: gpsd's ExecStart ran essentially simultaneously with
    # chrony's own ActiveEnterTimestamp, a genuine sub-second race the
    # ordering dependency alone doesn't close. ExecStartPre below waits
    # (bounded, never fails gpsd's own startup) for the socket file to
    # actually exist before gpsd's real ExecStart runs.
    sudo mkdir -p /etc/systemd/system/gpsd.service.d
    sudo tee /etc/systemd/system/gpsd.service.d/after-chrony.conf > /dev/null <<EOF
[Unit]
After=chrony.service
Wants=chrony.service

[Service]
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 20); do [ -S /run/chrony.clk.${GPS_TTY}.sock ] && exit 0; sleep 0.5; done; exit 0'
EOF

    # gpsd.service itself starting after chrony isn't enough: the actual
    # device-attach command comes from a SEPARATE systemd unit,
    # gpsdctl@<tty>.service (udev-triggered directly off the device
    # appearing, via gpsd's own shipped udev rule - see the by-id/tty
    # comment above). Confirmed via `journalctl -b -u gpsdctl@ttyACM0` on
    # a real reboot 2026-09-12: it ran and successfully told gpsd to open
    # the device a full 14+ seconds BEFORE chrony.service even started,
    # well before gpsd.service's own chrony-ordered startup. gpsd's
    # internal per-device chrony-socket connection attempt happens at
    # that device-open moment, independent of whether the main gpsd
    # daemon is separately ordered after chrony - so this unit needs the
    # exact same ordering + wait treatment on its own.
    sudo mkdir -p /etc/systemd/system/gpsdctl@.service.d
    sudo tee /etc/systemd/system/gpsdctl@.service.d/after-chrony.conf > /dev/null <<EOF
[Unit]
After=chrony.service
Wants=chrony.service

[Service]
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 20); do [ -S /run/chrony.clk.${GPS_TTY}.sock ] && exit 0; sleep 0.5; done; exit 0'
EOF

    # Even with the socket existing and correctly named, gpsd's own writes
    # to it were still silently failing - not a DAC permission problem
    # (confirmed: works fine at the socket's default root:root 0755), but
    # Ubuntu/Debian's shipped gpsd AppArmor profile, which only allows the
    # legacy plain chrony.tty*.sock naming and has no rule at all for
    # gpsd 3.25+'s chrony.clk.<name>.sock convention. Confirmed via
    # `journalctl -k | grep apparmor` showing DENIED entries for this exact
    # socket path once the right log was checked. Covered by a local
    # override so it survives gpsd package upgrades.
    if [ -f /etc/apparmor.d/usr.sbin.gpsd ]; then
        APPARMOR_RULE='/{,var/}run/chrony.clk.*.sock rw,'
        APPARMOR_LOCAL=/etc/apparmor.d/local/usr.sbin.gpsd
        sudo touch "$APPARMOR_LOCAL"
        if ! grep -qF "$APPARMOR_RULE" "$APPARMOR_LOCAL" 2>/dev/null; then
            {
                echo ""
                echo "# Allow gpsd's modern chrony SOCK refclock naming (the .clk."
                echo "# infix gpsd 3.25+ uses) - added by Setup_Ham_Radio_Stack.sh"
                echo "$APPARMOR_RULE"
            } | sudo tee -a "$APPARMOR_LOCAL" > /dev/null
            sudo apparmor_parser -r /etc/apparmor.d/usr.sbin.gpsd
            echo "Added AppArmor override for gpsd's chrony SOCK refclock."
        fi
    fi

    sudo systemctl daemon-reload
    sudo systemctl enable --now chrony
    sudo systemctl restart gpsd
    echo "chrony configured with GPS refclock. Check with: chronyc sources -v"
    echo "NOTE: a device already attached to a running gpsd won't pick this up live -"
    echo "reboot (or 'sudo gpsdctl add <by-id path>' as a live-session workaround) for"
    echo "the GPS to actually reconnect."
else
    echo "No USB GPS detected under /dev/serial/by-id/ - enabling chrony with network NTP only."
    echo "Re-run this script once a GPS is connected to add the GPS refclock."
    sudo systemctl enable --now chrony
fi

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

section "Disabling CI-V Transceive on the radio"
# ON by default on the IC-705. Looked like a full fix for rigctld wedging
# (still listening but never answering any query) in one 2026-09-10 test
# session, then was disproven in the next one - WSJT-X still triggered the
# same wedge with this confirmed off. Left enabled anyway since it's a
# real, harmless improvement (stops unsolicited status broadcasts from
# interleaving with request/reply exchanges on the same CI-V line) and may
# still be A contributing factor even though it's not THE fix - see
# "rigctld can wedge" in README.md for the fuller, still-unresolved
# picture. No effect on VarAC/WSJT-X/JS8Call/Pat, which all poll for state
# explicitly instead of relying on these broadcasts.
#
# Resolved by glob instead of trusting config.sh's IC705_SERIAL_ID here:
# that field is only ever used as Start_Pat.sh's fallback default before
# select-radio.sh has been run once (see README), so on a station that's
# always used multi-radio profiles it can - and on this one, did - sit at
# its example placeholder indefinitely without anything actually being
# broken. This step needs the radio's real path regardless of that.
IC705_REAL_DEVICE=$(ls /dev/serial/by-id/*IC-705*-if00 2>/dev/null | head -1)
if [ -n "$IC705_REAL_DEVICE" ]; then
    python3 - "$IC705_REAL_DEVICE" <<'PYEOF' || echo "WARNING: couldn't disable CI-V Transceive - set it manually (Menu -> Set -> Connectors -> CI-V -> CI-V Transceive -> OFF) if rigctld wedges."
import sys
from serial import Serial
ser = Serial(sys.argv[1], 115200, timeout=2)
ser.write(bytes.fromhex("fefea4e01a05013100fd"))
reply = ser.read_until(expected=b"\xfd")
ser.close()
if reply[-2:-1] != b"\xfb":
    print(f"Unexpected reply: {reply.hex()}")
    sys.exit(1)
print("CI-V Transceive disabled.")
PYEOF
else
    echo "Skipped (radio's serial device not found - set this manually later if rigctld wedges)."
fi

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

section "Installing JS8Call, WSJT-X (distro repo), GridTracker (.deb package)"
# JS8Call and WSJT-X specifically from the distro repo, NOT the upstream
# GitHub .deb releases: GitHub's JS8Call build is Qt6, whose PipeWire
# integration has a real bug ("Requested [input/output] audio format is
# not supported on device") with no working fix found - Mint's own repo
# build is Qt5 and confirmed working. WSJT-X's GitHub build happens to be
# fine (Qt5 too), but installing both from the same source keeps them from
# drifting apart, and matches the general rule for this stack: prefer the
# distro repo over upstream .deb releases when both exist.
sudo apt install -y js8call wsjtx

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
# GridTracker has no distro repo package - this one really does need the
# upstream .deb.
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

section "Start_WSJTX.sh / Start_JS8Call.sh"
# Unlike Start_Pat.sh/Start_Pat_FM.sh, these never kill a pre-existing
# rigctld - WSJT-X, JS8Call, Pat, and Conky's display can all share one
# rigctld over the network at once. Each only starts rigctld if nothing's
# there yet, and only stops it again on exit if it's the one that started
# it - if it was already running (shared with something else), it's left
# alone for whatever else is using it.
for APP in WSJTX:wsjtx JS8Call:js8call; do
    SCRIPT_NAME="${APP%%:*}"
    BIN="${APP##*:}"
cat > "$HOME/Start_$SCRIPT_NAME.sh" <<EOF
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
fi

for var in RIG_MODEL RIG_NAME SERIAL_DEVICE BAUD_RATE; do
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

# Unlike Start_Pat.sh/Start_Pat_FM.sh, this never kills a pre-existing
# rigctld - WSJT-X, JS8Call, Pat, and Conky's display can all share one
# rigctld over the network at once, so a running instance here likely means
# something else is already using it and shouldn't be yanked out from
# under it.
#
# The trap is registered up front, before anything is started - not after,
# like a first version of this script had it. That version left a wedged
# rigctld running as an orphan on the exact failure path below (rigctld
# started but never became responsive): the early \`exit 1\` ran before the
# trap was ever registered, so cleanup() never fired. Confirmed 2026-09-10.
WE_STARTED_RIGCTLD=0
cleanup() {
    if [ "\$WE_STARTED_RIGCTLD" = "1" ]; then
        pkill -f "^rigctld " 2>/dev/null || true
    fi
}
trap cleanup EXIT

if ! rigctld_responsive; then
    WE_STARTED_RIGCTLD=1
    PTT_ARGS=()
    [ -n "\$PTT_TYPE" ] && PTT_ARGS=(-P "\$PTT_TYPE")
    # Up to two attempts: rigctld itself has been seen to come up wedged
    # (listening but never answering) on a fresh start, not just as a
    # stale leftover - if the first attempt doesn't become responsive
    # within 10s, kill it and try once more before giving up.
    for attempt in 1 2; do
        rigctld -m "\$RIG_MODEL" -r "\$SERIAL_DEVICE" -s "\$BAUD_RATE" "\${PTT_ARGS[@]}" -t 4532 &
        for i in \$(seq 1 10); do
            rigctld_responsive && break 2
            sleep 1
        done
        echo "rigctld didn't respond within 10s (attempt \$attempt/2)..."
        pkill -f "^rigctld " 2>/dev/null || true
        sleep 1
    done
    if ! rigctld_responsive; then
        echo "ERROR: rigctld didn't come up talking to \$RIG_NAME after 2 attempts."
        echo "Double check SERIAL_DEVICE/BAUD_RATE in \$ACTIVE against the radio."
        exit 1
    fi
fi

$BIN
EOF
    chmod +x "$HOME/Start_$SCRIPT_NAME.sh"
done
echo "Start_WSJTX.sh and Start_JS8Call.sh written (radio-agnostic via active-radio.conf)."

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

section "fix-rigctld.sh"
cat > "$HOME/.local/bin/fix-rigctld.sh" <<'EOF'
#!/bin/bash
# Clears a wedged rigctld - still running and listening on port 4532, but
# no longer answering any query (a plain `rigctl f` hangs instead of
# erroring). See "rigctld can wedge" in README.md - not fully understood
# yet, but killing it and letting the next launcher start a fresh one has
# cleared it every time so far. Radio hardware is never affected.
if pgrep -f "^rigctld " > /dev/null; then
    echo "Stopping rigctld..."
    pkill -f "^rigctld " 2>/dev/null
    sleep 1
    echo "Done. Relaunch whichever app you were using (Pat/VarAC/WSJT-X/JS8Call) -"
    echo "it'll start a fresh rigctld automatically."
else
    echo "No rigctld running - nothing to fix."
fi
EOF
chmod +x "$HOME/.local/bin/fix-rigctld.sh"

cat > "$HOME/Desktop/Fix Rig Control.desktop" <<EOF
[Desktop Entry]
Name=Fix Rig Control
Comment=Clears a wedged rigctld (WSJT-X/JS8Call/Pat won't connect - see README)
Exec=bash -c "\$HOME/.local/bin/fix-rigctld.sh; echo; read -p 'Press Enter to close...'"
Type=Application
Terminal=true
Icon=process-stop
Categories=HamRadio;
EOF
chmod +x "$HOME/Desktop/Fix Rig Control.desktop"
echo "fix-rigctld.sh and its Desktop shortcut written."

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

# Conky can crash at autostart on some boots - confirmed 2026-09-12 via a
# core dump: it queries X11 window properties (XGetWindowProperty) while
# finding the desktop window to draw on, and if that races against the
# desktop/window manager not being fully ready yet at very early login,
# the X server can return a protocol error (e.g. BadWindow) that aborts
# the whole process - not a config problem, and not reliably reproducible
# (many prior boots this same session came up fine). Retry once after a
# short delay rather than silently staying gone for the rest of the
# session if it loses that race.
cat > "$HOME/.config/autostart/conky.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Conky (Ham Radio Status)
Exec=bash -c 'conky -c $HOME/.config/conky/conky.conf || (sleep 5 && conky -c $HOME/.config/conky/conky.conf)'
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

cat > "$HOME/Desktop/WSJT-X.desktop" <<EOF
[Desktop Entry]
Name=WSJT-X
Comment=Starts rigctld first if it isn't already running
Exec=$HOME/Start_WSJTX.sh
Type=Application
StartupNotify=true
Icon=wsjtx_icon
Terminal=false
EOF

cat > "$HOME/Desktop/JS8Call.desktop" <<EOF
[Desktop Entry]
Name=JS8Call
Comment=Starts rigctld first if it isn't already running
Exec=$HOME/Start_JS8Call.sh
Type=Application
StartupNotify=true
Icon=js8call_icon
Terminal=false
EOF

if [ -f "$SCRIPT_DIR/channel-tools/channel-picker.py" ]; then
    if ! compgen -G "$SCRIPT_DIR/channel-tools/channels_*.json" > /dev/null; then
        echo "Building the channel index(es) from the tracked CSVs..."
        (cd "$SCRIPT_DIR/channel-tools" && python3 build_channel_index.py) || \
            echo "WARNING: build_channel_index.py failed - see channel-tools/README.md."
    fi
cat > "$HOME/Desktop/Channel Picker.desktop" <<EOF
[Desktop Entry]
Name=Channel Picker
Comment=Browse programmed memory channels by name/group and jump to one
Exec=python3 "$SCRIPT_DIR/channel-tools/channel-picker.py"
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
