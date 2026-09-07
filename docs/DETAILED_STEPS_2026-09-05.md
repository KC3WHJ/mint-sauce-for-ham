# Detailed Rebuild Steps — ham-mintsauce (2026-09-05)

## 1. Locating recoverable material

The external drive's own Trash (`.Trash-1000` on `/media/ham/external`)
contained three items deleted together on 2026-09-04 at 23:27, from when
the machine was still hostnamed `ham-mint`:

- `laptop-backup-ham-mint-20260904-1721/root-backup.tar.zst` — an 18GB
  full-root backup taken at 17:21 that day.
- `ham_radio_backups/ham_radio_backup_2026-09-03_020720.tar.gz` — an
  earlier 1GB backup of just the radio-software home directory.
- `backup-scripts/` — `backup.sh` and an interactive `restore.sh`.

A newer, non-deleted 6.5GB backup on the drive root turned out to be a
backup of the *current* (freshly wiped) machine state, taken right after
the cleanup — confirming the live machine really was a bare Mint install
with none of the ham radio stack.

Inside the old backup's `home/ham/mint-sauce-for-ham/` was a git repo —
the polished, generalized successor to an earlier draft script
(`mint-adsb-sdr-recipe.sh`) — containing `Setup_Ham_Radio_Stack.sh`,
`config.sh.example`, `README.md`, and `SYNOPSIS.md`. This script already
combines the ADS-B/SDR stack and the full IC-705 digital-modes stack in
one idempotent, config-driven pass, and became the basis for the rebuild
instead of a live full-root restore (which the backup's own `restore.sh`
explicitly warns against running on a booted system).

## 2. Extracting what was needed from the old backup

Rather than restoring the whole archive, individual paths were pulled out
with `zstd -dc root-backup.tar.zst | tar -xf - <path>`:

- `home/ham/mint-sauce-for-ham/` (the setup script itself)
- `home/ham/radio_profiles/` and `home/ham/Start_Pat_Radio.sh` (multi-radio
  support for IC-7300/FT-891/G90/TX-500/µSDX, for future use)
- `home/ham/Documents/Claude_Session_mint-sauce-for-ham.txt` (a reference
  note pointing to the project's GitHub repo, no credentials)

Installer files (`VarAC_Installer_V15_0_18.exe`, VARA HF/FM setup `.exe`s,
`pat_*.deb`, `GridTracker2*.deb`) were found already staged in a
`Ham Radio Build Downlods` folder on the drive itself and copied into
`~/Downloads`.

## 3. Configuring the script

`~/mint-sauce-for-ham/config.sh` was created from `config.sh.example` and
filled in with recovered identity details (from the old
`Setup_Ham_Radio_Stack.sh` copy and later from a station-info reference):
`CALLSIGN=N0CALL`, `GRID=AA00aa`, `IC705_SERIAL_ID` (the radio's USB
serial ID), `AUDIO_DEVICE=hw:1,0`. `WINLINK_PASSWORD` and `VARA_REG_CODE`
were filled in once that information was provided later in the session.

## 4. Phase 1 — sudo, non-interactive provisioning

A consolidated script installed everything requiring root but no user
interaction: system packages (`wine`, `winetricks`, `libhamlib-utils`,
`rtl-sdr`, `gpsd`, `flrig`, etc.), the RTL-SDR DVB-T driver blacklist,
`readsb`/`tar1090` (via wiedehopf's installers), `gpsd` config, `readsb`
wired to gpsd, both services enabled, SDR++ installed, and the SDR++
VHF/HF mode-switch helper scripts dropped into `/usr/local/bin`.

One correction needed: the package is named `libhamlib-utils` on this
Ubuntu Noble base, not `hamlib-utils` as originally scripted — the first
run failed with "Unable to locate package" until fixed.

A second small sudo pass installed the two `.deb` packages
(`pat_1.0.0_linux_amd64.deb`, `GridTracker2-*.deb`) that had been missed
from the first pass.

## 5. Phase 2 — non-sudo configuration

With root access on my end limited (sudo is cached per-tty and this
session's shell has no controlling tty, so all `sudo` steps had to be run
by the user directly), everything not requiring elevation was scripted
directly: the Wine prefix (`~/.wine32`, 32-bit) and winetricks baseline
(`corefonts gdiplus vb6run pdh_nt4 win7 sound=alsa`), VARA HF/FM audio and
registration config, the Pat Winlink `~/.config/pat/config.json`,
`Start_Pat.sh`/`Start_Pat_FM.sh` launchers, `Start_VarAC.sh`, and Desktop
shortcuts for tar1090, readsb start/stop, both SDR++ modes, and Pat
Winlink HF/FM.

## 6. Serial port permissions

The IC-705 and a USB GPS receiver were both detected under
`/dev/serial/by-id/`, but `rigctld` failed with "Permission denied" —
the `ham` user was missing from the `dialout` group (owner of
`/dev/ttyACM*`). Fixed with `sudo usermod -aG dialout ham`, which required
a full logout/reboot to take effect (group membership is per-login-session,
not live-reloadable).

## 7. Wine app installers

VarAC, VARA HF, and VARA FM were installed by launching each `.exe` under
Wine (this session has X11 display access, so installer windows appeared
on-screen for the user to click through) and verified by checking for
each app's installed `.exe` inside the Wine prefix afterward.

## 8. ADS-B Exchange feed

Run interactively (`sudo bash -c "$(curl -L https://adsbexchange.com/feed.sh)"`)
by the user, since it uses whiptail dialogs needing a real terminal.
Verified via `systemctl is-active adsbexchange-feed adsbexchange-mlat` and
the live process list. The feeder name it came up under (`EE-KPNE`) didn't
match the documented `EE-KPHL` and was corrected in
`/etc/default/adsbexchange` followed by a service restart.

## 9. VarAC's Wine Mono requirement

Launching VarAC initially failed silently with
`Wine Mono is not installed`, then (after installing `wine-mono-9.4.0`)
with a Mono-internal `gpath.c` assertion — resolved by upgrading to the
latest release, `wine-mono-11.3.0`, downloaded directly from
`dl.winehq.org` and installed via `wine msiexec /i ... /qn`. After that,
VarAC's main window opened successfully (confirmed via `xwininfo`, since
its window isn't registered with the window manager's taskbar list).

## 10. flrig for VarAC's CAT/PTT path

`Start_VarAC.sh` launches flrig alongside VarAC; flrig itself needed a
one-time manual setup (Icom IC-705, `/dev/ttyACM1`, 115200 baud) done by
the user in its GUI. Its Initialize step first failed with "transceiver
not responding" because a leftover `rigctld` test instance was still
holding the serial port exclusively — killing it resolved the conflict
and flrig connected successfully.

## 11. VarAC settings

- **Rig control**: PTT Configuration and Frequency Control both set to
  flrig at `127.0.0.1:12345`.
- **Registration**: VARA HF's registration code was entered by the user
  directly in its GUI; the same code and callsign were then copied into
  VARA FM's `.ini` by direct file edit (it wasn't running at the time).
  VARA FM's audio device settings, which an earlier automated step had
  skipped (no registration code was available yet at that point), were
  copied in from VARA HF's config the same way.
- **Backup directory error**: clicking Save on the Rig settings tab
  consistently threw "backup directory does not exist," even though the
  directory existed, was writable, and real backups were landing in it.
  Comparing `VarAC.ini` before and after each save attempt showed the
  actual settings write always succeeded regardless of the error —
  identified as a cosmetic Wine-specific bug in VarAC's Save routine, not
  a real problem. `AutomaticBackup` was set to `OFF` to reduce how often
  the buggy check fires. When one save attempt appeared completely stuck,
  the exact target field values (`RigPTTControlType=FLRIG`,
  `RigFreqControlType=FLRIG`, `FlrigHost=127.0.0.1`) were written directly
  into `VarAC.ini` while VarAC was closed, bypassing the GUI save entirely.
- The VarAC Desktop shortcut originally launched `VarAC.exe` directly
  (bypassing flrig); its `Exec=` line was changed to run `~/Start_VarAC.sh`
  instead, so double-clicking it brings up flrig automatically too.

## 12. WSJT-X / JS8Call radio control: rigctld vs. flrig

A real conflict surfaced between two recovered documents: a station-info
reference said WSJT-X/JS8Call should use flrig, while an earlier "Ham
Radio Software Setup" summary explicitly said both had been switched
*away* from flrig to direct `rigctld` because flrig was "a recurring,
hard-to-diagnose source of hangs and crashes." The direct-rigctld path was
chosen, matching the documented stability fix — both apps are configured
with Rig: "Hamlib NET rigctl", Network Server `127.0.0.1:4532`, PTT
Method: CAT. (`WSJT-X.ini`'s `CATNetworkPort=127.0.0.1:4532` later
confirmed this was set correctly.)

## 13. GridTracker and JS8Call UDP alignment

`GridTracker2` was installed via `.deb` but never launched during initial
setup, so its config didn't exist yet, and JS8Call's own `.ini` didn't
exist until the user ran it at least once. Once `~/.config/JS8Call.ini`
existed, its `UDPEnabled`/`UDPServerPort` were set to `true`/`2237` to
match WSJT-X (already correct by default) and GridTracker's listening
port. GridTracker2 was then launched directly
(`/opt/GridTracker2/gridtracker2`) and confirmed running.

## 14. Conky station-status monitor

Built from scratch: `~/.config/conky/conky.conf` plus two helper scripts,
`~/.local/bin/ham-radio-freq.sh` and `~/.local/bin/ham-radio-mode.sh`,
each checking `rigctld` (Hamlib `f`/`m` commands) first and falling back
to flrig's XML-RPC interface (`rig.get_vfo`, `rig.get_mode`) so the
display stays accurate no matter which app currently has the radio.
`~/.local/bin/ham-gps-grid.sh` computes a Maidenhead grid square from a
live `gpsd` fix via `gpspipe` and a short Python conversion, verified
against the documented grid square (`AA00aa`) before wiring it in.

Went through a few rounds of visual polish per request: a dark
semi-transparent panel with section headers (RADIO/APPS/STATION), a blue
accent color (`#6fa8dc`) on "Station" in the title, then a UTC/Local time
+ `YYYY-MM-DD` date footer replacing a simpler clock line. Autostarts via
`~/.config/autostart/conky.desktop`.

Note: this session's shell has no controlling terminal and runs outside
the desktop session's process group, so `kill`/`pkill` against Conky's
detached background process consistently failed silently (or with a
non-standard exit code) — every Conky restart during development required
the user to run `pkill -f "conky -c"` themselves before a fresh instance
could be launched.

## 15. 10-minute station ID timer

A small Tkinter utility, `~/.local/bin/id-timer.py`: Start/Cancel buttons,
an MM:SS countdown, a single beep (`paplay` on
`/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga`) plus a
flashing red background at zero, then an automatic restart of the
countdown — repeating until Cancel is clicked. Styled to match Conky
exactly: same width (311px, Conky's actual rendered width, wider than its
280px configured minimum due to content overflow) and the same blue
(`#6fa8dc`) on a custom-drawn title bar, since window managers — not
applications — own native title bar coloring, requiring
`overrideredirect(True)` plus manually-implemented click-and-drag to move
the undecorated window. Positioned directly under Conky. Autostarts via
`~/.config/autostart/id-timer.desktop` (idle, showing Start, until
manually started each session).

## 16. Final verification

Every component was tested live, in this order: readsb/tar1090 map,
ADS-B Exchange feed, SDR++ Airband then HF/Shortwave (remembering to
restart `readsb` afterward, since the mode-switch scripts stop it to free
the shared RTL-SDR dongle — this was missed once and caught when "testing
ADS-B" turned up an inactive `readsb` service), VarAC (frequency change
and tune button over flrig), Pat Winlink HF, Pat Winlink FM, WSJT-X,
JS8Call, GridTracker, the Conky monitor (including the added Mode line),
and the full 10-minute ID timer cycle including its auto-reset.

Conky's live status display paid for itself twice during this process: it
caught `pat http` having been left running in the background after moving
on to other tests (stopped once noticed), and separately caught `readsb`
having been left stopped after SDR++ testing when "testing ADS-B" turned
up nothing — in both cases the fix was immediate once the monitor made
the stale state visible.

## 17. Full backup and documentation

Once live testing was complete, a full-root backup of the finished
machine was taken onto the external drive using the same approach as the
original `backup.sh` (`tar --acls --xattrs` piped through `zstd -T0`,
excluding pseudo-filesystems, caches, trash, and the destination itself),
producing a 4.8GB compressed archive (~12.3GB uncompressed, ~1.29M files)
verified with `zstd -t`. This synopsis and the accompanying detailed
step-by-step document (this file) were written alongside it in a
dedicated `Ham-Mint-Rebuild-Docs-20260905` folder on the same drive.

## 18. Publishing the corrected script back to GitHub

The user's existing `mint-sauce-for-ham` GitHub repository
(`github.com/N0CALL/mint-sauce-for-ham`) predated this rebuild and only
had 3 commits. Rather than leave the two real bugs found in this session
(the `hamlib-utils` package name, the missing `dialout` group step) as
local workarounds, they were fixed directly in the actual
`Setup_Ham_Radio_Stack.sh` recovered from backup, along with two
proactive improvements: installing `flrig` and Wine Mono automatically
(both had to be done manually mid-rebuild) and auto-repointing VarAC's
Desktop shortcut at `Start_VarAC.sh` after install. `README.md` was
updated with a "Fresh-install verification" section replacing its old
"not tested end-to-end" caveat.

Before publishing anything, every tracked file and the *entire* git
history (`git log --all -p`) was searched for the callsign, grid square,
real name, email, radio serial number, Winlink password, and VARA
registration code — none had ever been committed; the only appearances of
`N0CALL` anywhere were the repo's own clone URL and its git commit author
identity (`N0CALL@users.noreply.github.com`), both expected and not
sensitive. The `config.sh.example` placeholder (`N0CALL`/`AA00aa`) was
already generic, so no find-and-replace was needed there.

At the user's request, the old 3-commit history was then squashed
entirely: a `git checkout --orphan` branch was created, the current
(fixed) working tree committed as a single root commit, and that branch
replaced `main` locally. Since this machine had no GitHub credentials at
all, the user ran `gh auth login` themselves (browser-based device-code
flow) before `git push --force origin main` could run. The push was
verified afterward via `git fetch` + `git log origin/main` showing only
the one new commit.

Finally, the repository's GitHub metadata was updated to match: its
description was changed from "Trial Build for a Complete Ham Stack for
the IC-705 on Linux Mint" to a description of the verified build, and
topics (`ham-radio`, `sdr`, `ic-705`, `linux-mint`, `wine`, `ads-b`,
`winlink`) were added via `gh repo edit`.
