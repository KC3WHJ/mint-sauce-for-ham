# User Guide

A plain-language guide to every application this station installs — what
each one is for, how to start it, and how to use it day to day. For
installation, configuration, and troubleshooting internals, see
[README.md](README.md) instead; this guide assumes everything is already
set up and working.

## The one rule that matters most

**Only one radio-control program can talk to the radio at a time.** VarAC,
Pat Winlink (HF or FM), WSJT-X, JS8Call, Fldigi, and vARIM all need
exclusive access to the radio's serial (CAT) and audio connections — running
two at once corrupts both. Close whichever one you're not actively using
before opening another. If something won't connect and you're not sure
what's still running, use **Fix Rig Control** (see below).

The Channel Picker and ADS-B/SDR++ tools have the same rule among
themselves (Channel Picker briefly takes the radio for a moment when
jumping to a channel; SDR++ and readsb both want the one RTL-SDR dongle).

## Getting started: Select Radio

**Always do this first**, and again any time you physically switch which
radio is connected.

Double-click **Select Radio** on the Desktop. A text menu lists every radio
this station knows about (IC-705, IC-7300, FT-891, TX-500 MP, G-90) — pick
the one you actually have connected. This one choice is what every other
app below reads to know which serial port, audio device, and CAT settings
to use, so nothing else will work correctly until you've done this at least
once per session (it does **not** persist automatically across a reboot —
run it again after restarting the computer).

Choosing a radio also applies that radio's audio settings (the sound-card
names VARA, WSJT-X, JS8Call, Fldigi and Pat use) automatically, so you
don't need to re-enter audio devices by hand in those programs after
switching.

---

## Talking to people

### VarAC — real-time keyboard chat

A chat application, like instant messaging over radio, with file transfer
and a list of recently-heard stations. Good for casual contacts, calling
CQ, and short conversations.

- **Start it**: double-click **VarAC** on the Desktop. Three windows come
  up in sequence — flrig (rig control), VARA HF (the modem), then VarAC
  itself. Give it a few seconds for all three to connect; VarAC's top bar
  should show a live frequency once flrig connects.
- **Use it**: type in the message box at the bottom and hit Enter to
  transmit. The main pane shows incoming traffic and recently-heard
  stations you can click to reply to directly.
- **Stop it**: just close all three windows normally (not the X in the
  corner if it hangs — see Fix Rig Control). Closing VarAC cleanly (not
  force-killing it) is what lets flrig save its settings for next time.
- **First time with a brand-new radio**: flrig needs one manual setup step
  the very first time — see README.md's "Not fully hands-off" section if
  you get a "Transceiver not responding" error the first time you try a
  radio here.

### Pat Winlink (HF) / Pat Winlink (FM) — radio email

Send and receive real email (including to the regular internet) over the
radio, no internet connection needed at your end. Use **HF** for long-range
HF-band email, **FM** for local VHF/UHF email via a Winlink FM gateway
station.

- **Start it**: double-click **Pat Winlink (HF)** or **Pat Winlink (FM)**.
  A terminal window shows startup progress (starting rig control, then the
  VARA modem), and your web browser opens automatically to
  `http://localhost:8080` — that's Pat's actual interface, a webmail-style
  inbox.
- **Use it**: click **Compose** to write a message, or **Connect** to check
  for new mail. Pat handles the radio connection in the background; you
  never need to touch a terminal.
- **Stop it**: double-click **Stop Pat Winlink** — this cleanly shuts down
  Pat and whichever VARA engine it started, so nothing's left running in
  the background hogging the radio. Don't just close the browser tab; Pat
  keeps running until you actually stop it.

---

## Weak-signal & keyboard digital modes

### WSJT-X — FT8 and other weak-signal modes

The standard tool for FT8, FT4, and similar modes designed to complete
contacts even when the signal is barely above the noise floor. Mostly
automated once running — it decodes and can auto-reply to calls for you.

- **Start it**: double-click **WSJT-X**. It starts rig control in the
  background automatically if nothing else is already using it.
- **Use it**: the waterfall shows incoming signals; double-click a decoded
  call to start a contact, or enable auto-sequencing to let it run mostly
  on its own. **GridTracker** (find it in the applications menu, not a
  Desktop icon) runs alongside WSJT-X automatically and plots stations
  you've heard/worked on a map — no separate setup needed, it's already
  wired to WSJT-X's UDP reporting.

### JS8Call — keyboard-to-keyboard weak-signal chat

Like WSJT-X's underlying mode, but built for actual free-form typed
conversation instead of just exchanging signal reports — includes
message relay through other stations and store-and-forward.

- **Start it**: double-click **JS8Call**. Same automatic rig-control
  startup as WSJT-X.
- **Use it**: type in the message box and select **Send**. The band
  activity and "heard stations" panels on the right show what's audible.
- **CommStat** (see below) is a companion situational-awareness app built
  on top of JS8Call's data — run both together if you want the map/alert
  view.

### CommStat — situational-awareness map for JS8Call

Parses status reports (STATREPs) that JS8Call stations transmit and plots
them on a map, color-coded by category (power outage, road conditions,
etc.) — a way to see, at a glance, what a whole net of stations is
reporting.

- **Start it**: double-click **CommStat** on the Desktop. Run it alongside
  JS8Call — it connects to JS8Call's own TCP API (already configured for
  you), it doesn't talk to the radio directly itself.
- **Use it**: the map view fills in as STATREPs come in over JS8Call. Use
  the Groups panel to filter which nets/categories you're watching.
- **First-time setup**: on a machine that's never run CommStat before,
  you'll be asked for your callsign, grid, state, and which groups/nets to
  watch — this only happens once, it's saved from then on.
- **No radio? See the next section** — CommStat can also run against a web
  SDR instead of your own radio.

### Fldigi + Flmsg from a web SDR (no radio needed)

The same receive-only idea for AmRRON's Fldigi/Flmsg messaging: listen to a
net through a web SDR and read the traffic, with no radio and no chance of
transmitting. Separate from your real Fldigi and Flmsg, so it can run at the
same time as them (and as the JS8Call WebSDR above).

- **Start it**: double-click **Activate Fldigi WebSDR**. It opens a separate
  Fldigi (title bar says **WEBSDR-RX**) and a separate Flmsg. When it says so,
  play your WebSDR in the browser, press Enter in the terminal window, and
  pick the browser's audio stream from the menu. If JS8Call WebSDR is
  already running, the audio is already routed and you can skip that.
- **Tune it**: the AmRRON net frequencies are in its frequency list (book
  icon) - but a web SDR has its own tuning, so tune the web SDR (USB) to
  the net frequency, then match Fldigi's waterfall to the 900 Hz position.
- **Stop it**: double-click **Deactivate Fldigi WebSDR**. This closes only
  the WebSDR Fldigi and Flmsg; your real ones are never touched.
- Its Flmsg has its **own copy of the AmRRON forms** and its own saved
  messages, separate from your radio Flmsg's.

### JS8Call + CommStat from a web SDR (no radio needed)

Listen for JS8 stations through someone else's receiver on the internet
(websdr.org, kiwisdr.com, and similar) and see them in JS8Call and
CommStat. Receive-only: no radio, no rig control, and no transmitting,
so it's safe to use at any time. It's completely separate from your real
JS8Call and CommStat, so **it doesn't break the "one radio program at a
time" rule** and can run while a radio program is open.

- **Start it**: double-click **Activate JS8Call WebSDR** on the Desktop.
  It starts a separate JS8Call and a separate CommStat. When it says so,
  open your WebSDR page in your browser, start its audio playing, press
  Enter in the terminal window, and pick the browser's audio stream from
  the menu that appears.
- **Tell them apart**: the WebSDR CommStat's map uses the opposite theme
  (dark vs. light) from your normal CommStat, and its lists start out
  empty. It's connected only to the WebSDR JS8Call and never transmits or
  sends acknowledgements.
- **Stop it**: double-click **Deactivate JS8Call WebSDR**. This closes only
  the WebSDR copies and removes the virtual audio device. Your normal
  JS8Call and CommStat are never touched.
- **Don't** open the normal **CommStat** icon expecting it to show
  WebSDR traffic; it won't. Only Activate starts the WebSDR copy.

---

## AmRRON & traditional digital modes

### Fldigi — the general-purpose digital mode suite

The most broadly capable digital-mode tool here — supports a large number
of modes (PSK, MFSK, Olivia, RTTY, and more), used heavily by AmRRON's
own net structure. Comes with two companion tools:

- **Flmsg** — fills out standardized message forms (ICS forms, AmRRON's
  own custom forms) for passing structured traffic.
- **Flamp** — sends/receives files and repeated broadcasts layered on top
  of Fldigi.

Find Fldigi and Flmsg on the Desktop; Flamp is in the applications menu.
Fldigi also opens Flmsg by itself when a form arrives. Flmsg asks once, the
first time, whether you want the "Service Agency / Simple" or "Communicator /
Expert" screen, and for your details - that's a one-time choice.

- **Start it**: double-click **Fldigi**.
- **Use it**: pick a mode from the mode selector, watch the waterfall for
  activity, and use the transmit/receive panes like a simple chat window.
  For AmRRON nets specifically, they use Contestia 4/250 - open the
  frequency list (the **book icon**) and double-click **3.588**, **7.110**
  or **14.110 MHz** (80/40/20m): it sets the frequency, the mode and the
  waterfall position (900 Hz) in one step. Traffic is normally sent in
  MFSK32; with **RxID** on (green, top right) Fldigi switches mode for you
  and the sending station returns the net to Contestia 4/250 afterward.
  Keep **AFC off** (gray), and set the **squelch** slider just above the
  noise (lower it until squelch turns green, then raise it until it turns
  yellow) or Fldigi will "decode" noise into gibberish. These AmRRON
  settings are already applied for you; check amrron.com's current net
  schedule, since frequencies do shift over time.
- **AmRRON forms in Flmsg**: AmRRON's custom forms (STATREP, SITREP,
  SPOTREP, Blank Form) are already installed - in Flmsg, choose them from
  the custom forms list. Keep the older versions there; you need them to
  open traffic from stations that haven't updated.
- **No radio? Use the WebSDR version** (next section) - Fldigi + Flmsg fed
  from a web SDR, receive-only.

### vARIM — lightweight, open-source VARA HF chat

A second, open-source front-end for the VARA HF modem (VarAC is the other
one) — simpler, Linux-native, good if you want a lighter-weight chat client
or you're running this on something low-power like a Raspberry Pi.

- **Start it**: there's no Desktop icon for this one — open a terminal and
  type `varim`.
- **Use it**: connects to a running VARA HF modem over TCP; toggle its
  LISTEN state to accept incoming connections, send/receive messages in
  its main window.

---

## Reference & situational-awareness tools

### Channel Picker — browse and jump to programmed memory channels

**IC-705, IC-7300, and FT-891 only** — it does not work with the G-90 or
TX-500 MP. If one of those is the active radio, it fails with a clear "no
channel map" error rather than attempting anything; this is expected, not
a bug — see `channel-tools/README.md` for why (and what adding either
would take).

**TX-500 MP:** the Channel Picker can't program this radio directly, but
`channel-tools/README.md` explains two export routes: a CSV for Lab599's
TRX Remote phone app and a `.mem` file for the TRX Mem desktop program.

A desktop app listing every channel programmed into your radio's memory,
organized by group, with a one-click "go to this channel" button — much
faster than scrolling through memories on the radio's own small screen.

- **Start it**: double-click **Channel Picker**.
- **Use it**: click a channel in the list, then **Go to Channel**. The
  radio must already be in **MEMO mode** (not VFO) for this to actually
  change what's displayed — switch the radio to Memory mode first if
  nothing happens when you select a channel.
- It automatically stops rigctld/flrig if either is running before it
  talks to the radio, so you don't need to close them yourself first — it
  just won't restart them afterward, so relaunch whatever you were using
  before if you need radio control back.
- See `channel-tools/README.md` for how to add/edit channels — this app
  only browses what's already been programmed, it doesn't edit the list
  itself.

### VOACAP GUI — HF propagation prediction

Predicts which HF bands are likely to be open between your location and
anywhere else in the world, at a given time — useful for picking a band
before calling CQ, or deciding when to try to reach somewhere specific.

- **Start it**: double-click **VOACAP GUI**.
- **Use it**: enter a target location (or pick a preset), a date/time
  range, and it produces predicted signal reliability by band/hour. Doesn't
  need the radio at all — safe to run alongside anything else.

### Conky station monitor & ID Timer — always running, nothing to launch

These two start automatically when you log in and don't have Desktop
icons:

- **Conky** shows a small always-on-screen overlay with station status
  (callsign, grid, current radio/frequency if available, system info).
  Its frequency and mode are read in a way that doesn't disturb the radio
  (an earlier version made the G-90 click and flip VFOs; see
  Troubleshooting).
- **ID Timer** is a 10-minute countdown reminder to identify (state your
  callsign) during extended transmissions, per FCC rules — it has
  Start/Cancel buttons in its small window, docked just below Conky.

If either isn't showing after login, they may need to be started manually
once — see README.md's Conky/ID-timer section.

---

## SDR & ADS-B (aircraft tracking)

These all share the one RTL-SDR dongle — only one of {readsb, SDR++} can
use it at a time.

### ADS-B Map (tar1090) — live aircraft tracking

- **Start it**: double-click **ADS-B Map (tar1090)** — opens a live map of
  nearby aircraft in your browser. This assumes **Start readsb** is
  running (see below); if the map is empty, check that first.
- **Start readsb** / **Stop readsb**: readsb is the background service
  that actually decodes ADS-B signals from the dongle and feeds both the
  map and the ADS-B Exchange network. Start it before expecting the map
  or your feed status to show anything.

### SDR++ (Airband/VHF/UHF) / SDR++ (HF/Shortwave)

A general-purpose SDR receiver app — listen to anything the dongle can
tune to, not just ADS-B. Two shortcuts because the dongle needs to be in a
different internal mode for each range:

- **Airband/VHF/UHF** — normal tuner mode, for aircraft voice, ham
  2m/70cm, and similar.
- **HF/Shortwave** — direct-sampling mode for HF ham bands and shortwave
  broadcast. While this mode is active, airband/VHF/UHF reception doesn't
  work — switch back to the other shortcut when you're done.

Both shortcuts automatically stop `readsb` first, since it can't share the
dongle with SDR++ — remember to **Start readsb** again afterward if you
want ADS-B tracking back.

---

## Troubleshooting

### Fix Rig Control

If flrig or rigctld gets stuck ("wedged") — a radio-control app hangs on
launch, or shows no frequency/won't connect even though the radio is
clearly on — double-click **Fix Rig Control**. It's a one-click version of
"kill whatever's stuck and let the next thing you launch start clean,"
instead of hunting for a terminal to do it by hand.

### Nothing shows a frequency / "Transceiver not responding"

1. Did you run **Select Radio** this session? It doesn't persist across a
   reboot.
2. Is the radio actually powered on (not just USB-connected)?
3. Run **Fix Rig Control**, then try again.
4. If it's a radio you've genuinely never used with flrig/VarAC on this
   machine before, see README.md's note on flrig's one-time per-rig setup
   step — this is a real, expected one-time step, not a sign anything's
   broken.

### The radio clicks every few seconds and its frequency jumps

Something is polling the radio through the `rigctl` command on a timer,
which makes some radios (seen on the Xiegu G-90) flip between their A and
B VFOs and turn CAT red. The built-in Conky display no longer does this. If
you've added your own script or widget that runs `rigctl` repeatedly, have
it talk to rigctld's raw port (see README.md's note on this) or keep one
connection open instead. To find the culprit, close programs one at a time
and see when the clicking stops; a helper that runs `rigctl` every couple of
seconds will show up briefly in `ps`.

### Something won't start / shows old data

A few things on this station keep separate "deployed" copies that don't
always pick up updates automatically. If something's behaving in a way
that doesn't match this guide or the README, see README.md's "Hard-won
lessons" section — most surprising behavior here has already been run
down and documented there.
