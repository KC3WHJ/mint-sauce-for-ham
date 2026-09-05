# Synopsis

`mint-sauce-for-ham` is a single setup script that turns a stock Linux
Mint (or other Ubuntu-based) machine into a working ham radio + SDR
station. It covers two independent stacks that can be used together or
separately:

1. **ADS-B & general SDR reception** — an RTL-SDR dongle feeding readsb
   and tar1090 for live aircraft tracking (with a local map and an
   optional feed to ADS-B Exchange), plus SDR++ for general-purpose
   receiving across airband, VHF/UHF ham bands, HF ham bands, and
   shortwave broadcast.
2. **IC-705 digital modes** — VarAC, VARA HF, VARA FM, Pat Winlink,
   JS8Call, WSJT-X, and GridTracker, all sharing one Icom IC-705 through a
   single Hamlib `rigctld` bridge.

Nothing personal (callsign, grid square, radio serial number, Winlink
password, VARA registration code) is stored in the script itself — those
live in a `config.sh` file you create locally, which is excluded from
version control by `.gitignore`. Anyone cloning this repo starts from
placeholders in `config.sh.example` and fills in their own values.

The script is idempotent where practical: most sections check whether
something is already installed/configured before acting, so re-running it
after a partial run or a config change is safe.

# Steps

1. **Install prerequisites the script can't fetch for you.** VarAC, VARA
   HF, VARA FM (Windows installers) and the JS8Call/WSJT-X/GridTracker/Pat
   `.deb` packages are not freely redistributable. Download them yourself
   and drop them in `~/Downloads` (or wherever you'll point `DOWNLOADS` in
   step 3). Skip any of these if you don't plan to use that particular
   app — the script just skips installing what it can't find.

2. **Clone the repo.**
   ```bash
   git clone https://github.com/KC3WHJ/mint-sauce-for-ham.git
   cd mint-sauce-for-ham
   ```

3. **Create your local config.**
   ```bash
   cp config.sh.example config.sh
   nano config.sh
   ```
   Fill in your callsign, grid square, and (if using the IC-705 stack)
   `IC705_SERIAL_ID` — find it with `ls /dev/serial/by-id/` once the radio
   is plugged in. Leave `WINLINK_PASSWORD`/`VARA_REG_CODE` blank if you'd
   rather enter them by hand later inside each app. Leave
   `ADSB_LAT`/`ADSB_LON` blank to rely on a USB GPS instead of a fixed
   position.

4. **Run the script.**
   ```bash
   ./Setup_Ham_Radio_Stack.sh
   ```
   It prints a `=== section name ===` banner before each stage, so you can
   always see how far it's gotten. Two stages need you at the keyboard:
   - The ADS-B Exchange feed installer (whiptail dialogs asking for your
     station's lat/lon/altitude and, optionally, your ADS-B Exchange
     account UUID).
   - Each Wine installer window (VarAC, VARA HF, VARA FM) — click through
     the wizard once, then close it.

5. **Verify the ADS-B/SDR side.**
   - Open `http://localhost/tar1090/` for the live aircraft map.
   - Use the new "SDR++ (Airband/VHF/UHF)" or "SDR++ (HF/Shortwave)"
     Desktop shortcuts — not the plain SDR++ launcher — since only one RTL-SDR
     mode can be active at a time.
   - `readsb-start`/`readsb-stop` Desktop shortcuts free up the dongle for
     SDR++ when you need it.

6. **Verify the IC-705 side.**
   - Use the new "Pat Winlink (HF)" or "Pat Winlink (FM)" Desktop
     shortcuts, or `~/Start_VarAC.sh`, to bring up `rigctld` and the
     matching VARA mode automatically.
   - In WSJT-X/JS8Call, set Radio → Rig to "Hamlib NET rigctl", Network
     Server to `127.0.0.1:4532`, PTT Method to CAT. GridTracker needs no
     changes.
   - Remember: only one of {VarAC, Pat Winlink HF, Pat Winlink FM, WSJT-X,
     JS8Call} can run at a time — they all share the one radio.

7. **Read the reminders the script prints at the end** — it tells you
   exactly which optional pieces (Winlink password, VARA registration,
   fixed ADS-B location) were left blank and are still unconfigured.
