#!/usr/bin/env python3
"""IC-705 channel picker: browse programmed memory channels by name or group
and switch the radio to the selected one over CI-V.

Run build_channel_index.py at least once first (see README.md) so
ic705_channels.json exists alongside this script."""
import glob
import json
import os
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


def select_memory(group: int, slot: int):
    """Opens the serial port just long enough to switch the radio's active memory."""
    ser = Serial(find_ic705_port(), BAUD, timeout=1)
    try:
        for cmd, data in ((b"\x08\xA0", encode_bcd(group)), (b"\x08", encode_bcd(slot))):
            frame = b"\xfe\xfe" + TRANSCEIVER_ADDR + CONTROLLER_ADDR + cmd + data + b"\xfd"
            ser.write(frame)
            reply = ser.read_until(expected=b"\xfd")
            if reply and reply[-2:-1] == b"\xfa":
                raise RuntimeError("Radio rejected the command (NG reply)")
    finally:
        ser.close()


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
            select_memory(ch["group"], ch["slot"])
            self.status_var.set(f"Switched radio to CH{ch['channel_number']} — {ch['name']} ({ch['rx_mhz']:.4f} MHz)")
        except SerialException:
            self.status_var.set("Could not open the radio's serial port — is rigctld/flrig running?")
        except RuntimeError as e:
            self.status_var.set(str(e))


if __name__ == "__main__":
    ChannelPicker().mainloop()
