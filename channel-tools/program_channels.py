#!/usr/bin/env python3
"""Programs memory channels over CI-V from the per-section CSVs in this
directory, for whichever radio is active in ~/radio_profiles/active-radio.conf
(the same file every other launcher in this project uses). Self-contained
(only needs pyserial, already installed system-wide).

Usage:
    python3 program_channels.py            # program every channel for the active radio
    python3 program_channels.py 58         # program only channel 58 (e.g. after an edit)
    python3 program_channels.py 58 59 60   # program a specific set of channels
"""
import csv
import glob
import json
import os
import re
import sys
import time

from serial import Serial

BAUD = 115200
CONTROLLER_ADDR = bytes.fromhex("E0")
HERE = os.path.dirname(os.path.abspath(__file__))
ACTIVE_RADIO_CONF = os.path.expanduser("~/radio_profiles/active-radio.conf")

# ISS crossband channels: RX/TX are on completely different bands (not a normal
# duplex offset) -- not representable via the duplex-offset mechanism, skip.
SKIP_CHANNELS = {12, 13, 14, 15, 16}

MODE_FM = 0x05
FIL1 = 0x01

# CI-V operating-mode codes (cmd 0x06) -- stable across Icom's whole CI-V
# line (IC-7300/9700/705/etc, confirmed against Icom's official CI-V
# Reference Guide). FM-N has no distinct CI-V mode code (it's a filter
# setting, not a mode), so it maps to plain FM -- see README's "Known
# limitations" section.
MODE_CODES = {
    "LSB": 0x00,
    "USB": 0x01,
    "AM": 0x02,
    "CW": 0x03,
    "RTTY": 0x04,
    "FM": 0x05,
    "FM-N": 0x05,
    "WFM": 0x06,
    "CW-R": 0x07,
    "RTTY-R": 0x08,
}


def radio_key(rig_name: str) -> str:
    """'IC-705' -> 'ic705', 'IC-7300' -> 'ic7300' -- matches channel_maps/*.json
    filenames."""
    return re.sub(r"[^a-z0-9]", "", rig_name.lower())


def load_active_profile() -> dict:
    """Minimal parser for radio_profiles/*.conf's plain KEY="value" lines --
    these are sourced by bash elsewhere, but this tool only needs to read a
    handful of keys, not execute the file."""
    if not os.path.exists(ACTIVE_RADIO_CONF):
        raise SystemExit(f"ERROR: no radio selected -- run Select Radio first ({ACTIVE_RADIO_CONF} doesn't exist).")
    values = {}
    with open(ACTIVE_RADIO_CONF) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            values[key.strip()] = val.strip().strip('"')
    return values


def bcd_byte(hi_digit: int, lo_digit: int) -> int:
    return (hi_digit << 4) | lo_digit


def encode_bcd(value: int) -> bytes:
    """2-byte BCD, e.g. 58 -> b'\\x00\\x58'."""
    encoded = []
    while value > 0:
        low, high = value % 10, (value // 10) % 10
        encoded.append((high << 4) | low)
        value //= 100
    while len(encoded) < 2:
        encoded.append(0x00)
    encoded.reverse()
    return bytes(encoded)


def encode_frequency(freq_hz: int) -> bytes:
    """5-byte BCD little-endian frequency, per Icom's CI-V reference."""
    digits = f"{int(freq_hz):010d}"
    pairs = [digits[8:10], digits[6:8], digits[4:6], digits[2:4], digits[0:2]]
    return bytes(bcd_byte(int(p[0]), int(p[1])) for p in pairs)


def encode_offset(offset_hz: float) -> bytes:
    """3-byte BCD duplex offset, 100 Hz resolution (per Icom's CI-V reference)."""
    hz = round(offset_hz / 100) * 100
    digits = f"{int(hz):07d}"
    d_1m, d_100k, d_10k, d_1k, d_100h = (int(digits[-7]), int(digits[-6]), int(digits[-5]),
                                          int(digits[-4]), int(digits[-3]))
    return bytes([bcd_byte(d_1k, d_100h), bcd_byte(d_10k, d_100k), bcd_byte(0, d_1m)])


def encode_tone(freq: float) -> bytes:
    """3-byte BCD tone frequency (e.g. 131.8 -> 00 13 18)."""
    tenths = round(freq * 10)
    digits = f"{tenths:04d}"
    return bytes([0x00, bcd_byte(int(digits[0]), int(digits[1])), bcd_byte(int(digits[2]), int(digits[3]))])


def encode_name(name: str) -> bytes:
    return name.upper()[:16].ljust(16).encode("ascii", errors="replace")


class CivError(Exception):
    pass


class Radio:
    """Speaks the shared CI-V memory-programming sequence common to the
    whole Icom line. The one thing that differs by radio is how a memory
    channel is *selected* (select_memory) -- some radios (IC-705, IC-9700)
    have multi-band grouped memory needing an extra group-select frame
    (cmd 08 A0); others (IC-7300, HF/6m only, no bands to group) select a
    channel directly with a single cmd 08 frame. See MEMORY_GROUPS in
    radio_profiles/*.conf and README.md."""

    def __init__(self, profile: dict):
        self.ser = Serial(profile["SERIAL_DEVICE"], BAUD, timeout=1)
        self.transceiver_addr = bytes.fromhex(profile["CIV_ADDR"])
        self.memory_groups = profile.get("MEMORY_GROUPS", "true") == "true"

    def close(self):
        self.ser.close()

    def send(self, command: bytes, data: bytes = b"") -> bytes:
        frame = b"\xfe\xfe" + self.transceiver_addr + CONTROLLER_ADDR + command + data + b"\xfd"
        self.ser.write(frame)
        reply = self.ser.read_until(expected=b"\xfd")
        if not reply:
            raise CivError(f"Timeout waiting for reply to {command.hex()}")
        if reply[-2:-1] == b"\xfa":
            raise CivError(f"Radio rejected command {command.hex()} {data.hex()} (NG reply)")
        return reply

    def select_vfo_a(self):
        self.send(b"\x07", b"\x00")

    def set_frequency(self, hz: int):
        self.send(b"\x05", encode_frequency(hz))

    def set_mode(self, mode: str):
        code = MODE_CODES.get(mode.upper(), MODE_FM)
        self.send(b"\x06", bytes([code, FIL1]))

    def set_duplex(self, direction: str):
        code = {"simplex": 0x10, "-": 0x11, "+": 0x12}[direction]
        self.send(b"\x0F", bytes([code]))

    def set_offset(self, offset_hz: float):
        self.send(b"\x0D", encode_offset(offset_hz))

    def set_tone_type(self, on: bool):
        self.send(b"\x16", bytes([0x5D, 0x01 if on else 0x00]))

    def set_tone_freq(self, freq: float):
        self.send(b"\x1B", bytes([0x00]) + encode_tone(freq))

    def select_memory(self, group, channel: int):
        if self.memory_groups:
            self.send(b"\x08\xA0", encode_bcd(group))
        self.send(b"\x08", encode_bcd(channel))

    def memory_write(self):
        self.send(b"\x09")

    def read_memory_content(self, group, channel: int) -> bytes:
        # The "memory channel number" field in cmd 1A 00 matches whatever
        # select_memory() above just used: grouped radios (IC-705) address
        # a channel within cmd 1A 00 itself as group+channel (4-byte BCD,
        # this is how the original IC-705-only version of this tool worked,
        # confirmed against real hardware); flat radios (IC-7300) use just
        # the 2-byte BCD channel number, per Icom's official CI-V Reference
        # Guide for the IC-7300MK2 (p.17: "00 01 ~ 00 99: Memory channel
        # 01 ~ 99" -- no group field at all in that command's data).
        data = encode_bcd(group) + encode_bcd(channel) if self.memory_groups else encode_bcd(channel)
        reply = self.send(b"\x1A\x00", data)
        return reply[6:-1]  # strip FE FE dst src 1A 00 ... FD

    def write_memory_content(self, payload: bytes):
        self.send(b"\x1A\x00", payload)

    def program_channel(self, group, channel: int, rx_hz: int, tx_hz: int, mode: str, tone_mode: str, ctcss, name: str):
        self.select_vfo_a()
        self.set_frequency(rx_hz)
        self.set_mode(mode)
        if tx_hz != rx_hz:
            # cmd 0F means something different depending on the radio: on
            # grouped/VHF-UHF radios (IC-705) it's repeater duplex direction
            # (0x10/0x11/0x12); on flat/HF-only radios (IC-7300) that slot is
            # repurposed as the Split toggle (00/01) and rejects those values
            # outright (confirmed 2026-09-10 - a real NG reply, not a silent
            # no-op). Every channel this tool has ever needed to program on
            # an HF-only radio is simplex, so this whole block simply never
            # runs there in practice; skip it rather than pretend "set to
            # simplex" is a safe universal no-op to send.
            self.set_duplex("+" if tx_hz > rx_hz else "-")
            self.set_offset(abs(tx_hz - rx_hz))
        if tone_mode == "TONE" and ctcss:
            # set_tone_type() uses cmd 16 subcmd 5D, which is IC-705-
            # specific (the IC-7300 has no such subcommand at all - it
            # controls repeater tone/tone squelch as two separate ON/OFF
            # flags, cmd 16 42/43, not tested/wired up here since no
            # channel this tool has programmed on an HF-only radio needs
            # CTCSS). Fine as-is for grouped/VHF-UHF radios; revisit if a
            # flat-memory radio ever needs a toned channel.
            self.set_tone_type(True)
            self.set_tone_freq(float(ctcss))
        # else: leave tone alone rather than explicitly asserting "off" -
        # same reasoning as the duplex skip above, and confirmed the same
        # way (16 5D 00 got an NG reply from the IC-7300).
        self.select_memory(group, channel)
        self.memory_write()
        if self.memory_groups:
            time.sleep(0.1)
            payload = bytearray(self.read_memory_content(group, channel))
            payload[-16:] = encode_name(name)
            self.write_memory_content(bytes(payload))
        # else: skip the read-modify-write name patch on flat-memory radios.
        # Confirmed 2026-09-10 on a real IC-7300: cmd 09 above reliably
        # commits frequency/mode into the memory (verified against the
        # radio's own memory content readback), but a subsequent 1A 00
        # WRITE gets an NG reply from this radio's firmware the instant ANY
        # byte differs from what it just read back - true even for a
        # single-byte change deep in the name field with every other byte
        # byte-for-byte identical to a successful unmodified round-trip.
        # Not a byte-offset or character-encoding bug (both were verified
        # correct against Icom's own CI-V reference and cross-checked
        # programmatically against the known-correct frequency encoding).
        # Whatever precondition this radio actually wants isn't documented
        # in the CI-V Reference Guide as fetched, and further guessing
        # against live memory writes wasn't worth the risk. The channel
        # still gets the right frequency/mode; only its on-radio display
        # name is left at the radio's own default. Channel Picker itself is
        # unaffected - it reads names from channels_<radio>.json, not from
        # the radio's own memory content.


def load_channels(radio_key: str):
    map_path = os.path.join(HERE, "channel_maps", f"{radio_key}.json")
    if not os.path.exists(map_path):
        raise SystemExit(f"ERROR: no channel map for '{radio_key}' at {map_path}. See README.md.")
    with open(map_path) as f:
        sections = json.load(f)
    rows = []
    for path in sorted(glob.glob(f"{HERE}/*.csv")):
        section_key = os.path.basename(path).removesuffix(".csv")
        if section_key not in sections:
            continue
        meta = sections[section_key]
        group, base = meta.get("group"), meta["base_channel"]
        with open(path, newline="") as f:
            for row in csv.DictReader(f):
                ch = int(row["Channel Number"])
                row["_group"] = group
                row["_slot"] = ch - base + 1
                rows.append(row)
    rows.sort(key=lambda r: int(r["Channel Number"]))
    return rows


def main():
    only = {int(a) for a in sys.argv[1:]} if len(sys.argv) > 1 else None
    profile = load_active_profile()
    key = radio_key(profile.get("RIG_NAME", ""))
    print(f"Programming channels for {profile.get('RIG_NAME', '?')} ({key})...")
    rows = load_channels(key)
    radio = Radio(profile)
    done, skipped, failed = [], [], []
    try:
        for row in rows:
            ch = int(row["Channel Number"])
            if only and ch not in only:
                continue
            if ch in SKIP_CHANNELS:
                skipped.append(ch)
                continue
            rx_hz = round(float(row["Receive Frequency"]) * 1_000_000)
            tx_hz = round(float(row["Transmit Frequency"]) * 1_000_000)
            group, slot = row["_group"], row["_slot"]
            mode = row["Operating Mode"]
            if mode.upper() not in MODE_CODES:
                print(f"  WARNING: unrecognized Operating Mode '{mode}' for CH{ch:03d} -- defaulting to FM")
            print(f"CH{ch:03d}  group={group} slot={slot}  RX={rx_hz/1e6:.4f}  TX={tx_hz/1e6:.4f}  mode={mode}  "
                  f"{row['Tone Mode']} {row.get('CTCSS', '')}  name={row['Name']}")
            try:
                radio.program_channel(group, slot, rx_hz, tx_hz, mode, row["Tone Mode"], row.get("CTCSS"), row["Name"])
                done.append(ch)
            except CivError as e:
                print(f"  !! FAILED: {e}")
                failed.append(ch)
    finally:
        radio.close()
    print(f"\nProgrammed {len(done)} channels. Skipped (manual-only): {sorted(skipped)}. Failed: {sorted(failed)}")


if __name__ == "__main__":
    main()
