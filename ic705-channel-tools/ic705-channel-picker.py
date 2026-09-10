#!/usr/bin/env python3
"""IC-705 channel picker: browse programmed memory channels by name or group
and switch the radio to the selected one over CI-V.

Run build_channel_index.py at least once first (see README.md) so
ic705_channels.json exists alongside this script."""
import glob
import json
import os
import subprocess
import time
import tkinter as tk
from tkinter import ttk

from serial import Serial, SerialException

BAUD = 115200
TRANSCEIVER_ADDR = bytes.fromhex("A4")
CONTROLLER_ADDR = bytes.fromhex("E0")
HERE = os.path.dirname(os.path.abspath(__file__))
CHANNELS_FILE = os.path.join(HERE, "ic705_channels.json")
SECTIONS_FILE = os.path.join(HERE, "sections.json")


def encode_bcd(value: int) -> bytes:
    encoded = []
    while value > 0:
        low, high = value % 10, (value // 10) % 10
        encoded.append((high << 4) | low)
        value //= 100
    while len(encoded) < 2:
        encoded.append(0x00)
    encoded.reverse()
    return bytes(encoded)


def find_ic705_port() -> str:
    """Resolves the IC-705's CI-V serial port via its stable by-id symlink,
    since raw /dev/ttyACMx numbering depends on USB enumeration order and
    can point at a different device (e.g. a USB GPS receiver) across
    reboots or replugs."""
    matches = sorted(glob.glob("/dev/serial/by-id/*IC-705*-if00"))
    if not matches:
        raise SerialException("IC-705 not found under /dev/serial/by-id/ (is it plugged in?)")
    return matches[0]


def stop_conflicting_processes() -> list[str]:
    """rigctld/flrig also talk CI-V directly to the radio's one serial port -
    two processes writing raw bytes to the same physical UART at once
    corrupts both exchanges (confirmed 2026-09-10: with rigctld running,
    select_memory()'s writes/reads got silently corrupted - no exception,
    just no effect on the radio, since a timed-out/garbled reply isn't the
    same as an explicit NG reply). Same conflict Start_VarAC.sh already
    handles by stopping rigctld first; mirrored here for the same reason.
    Returns the names of whatever was actually stopped, for a status message.
    """
    stopped = []
    if subprocess.run(["pgrep", "-f", "^rigctld "],
                       capture_output=True).returncode == 0:
        subprocess.run(["pkill", "-f", "^rigctld "])
        stopped.append("rigctld")
    if subprocess.run(["pgrep", "-x", "flrig"],
                       capture_output=True).returncode == 0:
        subprocess.run(["pkill", "-x", "flrig"])
        stopped.append("flrig")
    if stopped:
        time.sleep(1)
    return stopped


def select_memory(group: int, slot: int) -> list[str]:
    """Opens the serial port just long enough to switch the radio's active
    memory. Returns the names of any conflicting process that had to be
    stopped first (see stop_conflicting_processes), so the caller can tell
    the user - they aren't restarted automatically, since this tool has no
    way to know which one (if any) the user wants back."""
    stopped = stop_conflicting_processes()
    ser = Serial(find_ic705_port(), BAUD, timeout=1)
    try:
        for cmd, data in ((b"\x08\xA0", encode_bcd(group)), (b"\x08", encode_bcd(slot))):
            frame = b"\xfe\xfe" + TRANSCEIVER_ADDR + CONTROLLER_ADDR + cmd + data + b"\xfd"
            ser.write(frame)
            reply = ser.read_until(expected=b"\xfd")
            if not reply or reply[-2:-1] != b"\xfb":
                # \xfb = OK, \xfa = NG - but treat anything other than an
                # explicit OK as failure, not just an explicit NG. An empty/
                # truncated reply (e.g. a timeout) is NOT success and must
                # not be treated as one.
                reason = "no reply (timed out)" if not reply else "rejected (NG) or garbled reply"
                raise RuntimeError(f"Radio did not confirm the command - {reason}")
    finally:
        ser.close()
    return stopped


class ChannelPicker(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("IC-705 Channel Picker")
        self.geometry("580x640")

        with open(CHANNELS_FILE) as f:
            self.channels = json.load(f)
        with open(SECTIONS_FILE) as f:
            section_meta = json.load(f)
        ordered_meta = sorted(section_meta.values(), key=lambda m: m["group"])
        self.sections = ["All groups"] + [m["display_name"] for m in ordered_meta]

        top = ttk.Frame(self, padding=8)
        top.pack(fill="x")
        ttk.Label(top, text="Search name or group:").pack(side="left")
        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", lambda *_: self.refresh())
        ttk.Entry(top, textvariable=self.search_var).pack(side="left", fill="x", expand=True, padx=(4, 12))

        ttk.Label(top, text="Group:").pack(side="left")
        self.section_var = tk.StringVar(value=self.sections[0])
        section_menu = ttk.Combobox(top, textvariable=self.section_var, values=self.sections, state="readonly", width=22)
        section_menu.pack(side="left")
        section_menu.bind("<<ComboboxSelected>>", lambda *_: self.refresh())

        legend_frame = ttk.LabelFrame(self, text="What each group is for", padding=6)
        legend_frame.pack(fill="x", padx=8, pady=(0, 8))
        legend_text = tk.Text(legend_frame, height=6, wrap="word", relief="flat",
                               background=self.cget("background"), font=("TkDefaultFont", 9))
        for meta in ordered_meta:
            legend_text.insert("end", f"{meta['display_name']}: ", ("bold",))
            legend_text.insert("end", f"{meta.get('description', '')}\n")
        legend_text.tag_configure("bold", font=("TkDefaultFont", 9, "bold"))
        legend_text.configure(state="disabled")
        legend_scroll = ttk.Scrollbar(legend_frame, command=legend_text.yview)
        legend_text.configure(yscrollcommand=legend_scroll.set)
        legend_text.pack(side="left", fill="both", expand=True)
        legend_scroll.pack(side="right", fill="y")

        columns = ("ch", "name", "freq", "note")
        self.tree = ttk.Treeview(self, columns=columns, show="headings", selectmode="browse")
        for col, label, width in (("ch", "CH", 50), ("name", "Name", 120), ("freq", "RX Freq", 100),
                                   ("note", "Note", 120)):
            self.tree.heading(col, text=label)
            self.tree.column(col, width=width, anchor="w")
        self.tree.pack(fill="both", expand=True, padx=8, pady=(0, 8))
        self.tree.bind("<Double-1>", lambda *_: self.go_to_selected())

        bottom = ttk.Frame(self, padding=(8, 0, 8, 8))
        bottom.pack(fill="x")
        self.status_var = tk.StringVar(value="Select a channel and click “Go to Channel”")
        ttk.Label(bottom, textvariable=self.status_var).pack(side="left")
        ttk.Button(bottom, text="Go to Channel", command=self.go_to_selected).pack(side="right")

        ttk.Label(self, text="Tip: the radio must be in MEMO mode (VFO/MEMORY icon → [MEMO]) for this to work.",
                  foreground="#666666", font=("TkDefaultFont", 8)).pack(fill="x", padx=8, pady=(0, 6))

        self.refresh()

    def refresh(self):
        query = self.search_var.get().strip().upper()
        section = self.section_var.get()
        self.tree.delete(*self.tree.get_children())
        for c in self.channels:
            if query and query not in c["name"].upper() and query not in c["section"].upper():
                continue
            if section != "All groups" and c["section"] != section:
                continue
            note = "MANUAL ONLY" if c["manual_only"] else ("RX only" if c["rx_only"] else "")
            self.tree.insert("", "end", iid=str(c["channel_number"]),
                              values=(c["channel_number"], c["name"], f"{c['rx_mhz']:.4f}", note))

    def go_to_selected(self):
        sel = self.tree.selection()
        if not sel:
            self.status_var.set("No channel selected")
            return
        ch = next(c for c in self.channels if c["channel_number"] == int(sel[0]))
        if ch["manual_only"]:
            self.status_var.set(f"CH{ch['channel_number']} ({ch['name']}) is manual-only — not programmed on the radio")
            return
        try:
            stopped = select_memory(ch["group"], ch["slot"])
            msg = f"Switched radio to CH{ch['channel_number']} — {ch['name']} ({ch['rx_mhz']:.4f} MHz)"
            if stopped:
                msg += f" (stopped {' and '.join(stopped)} first — restart it yourself if you need it back)"
            self.status_var.set(msg)
        except SerialException:
            self.status_var.set("Could not open the radio's serial port — is it plugged in?")
        except RuntimeError as e:
            self.status_var.set(str(e))


if __name__ == "__main__":
    ChannelPicker().mainloop()
