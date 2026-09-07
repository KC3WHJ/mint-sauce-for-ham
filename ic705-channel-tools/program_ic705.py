#!/usr/bin/env python3
"""Programs IC-705 memory channels over CI-V from the per-section CSVs in this
directory. Self-contained (only needs pyserial, already installed system-wide).

Usage:
    python3 program_ic705.py            # program every channel
    python3 program_ic705.py 58         # program only channel 58 (e.g. after an edit)
    python3 program_ic705.py 58 59 60   # program a specific set of channels
"""
import csv
import glob
import json
import os
import sys
import time

from serial import Serial

PORT = "/dev/ttyACM0"
BAUD = 115200
TRANSCEIVER_ADDR = bytes.fromhex("A4")
CONTROLLER_ADDR = bytes.fromhex("E0")
HERE = os.path.dirname(os.path.abspath(__file__))

# ISS crossband channels: RX/TX are on completely different bands (not a normal
# duplex offset) -- not representable via the duplex-offset mechanism, skip.
SKIP_CHANNELS = {12, 13, 14, 15, 16}

MODE_FM = 0x05
FIL1 = 0x01

# IC-705 CI-V operating-mode codes (cmd 0x06) -- stable across Icom's whole
# CI-V line (IC-7300/9700/705/etc). FM-N has no distinct CI-V mode code (it's
# a filter setting, not a mode), so it maps to plain FM like MODE_FM did
# unconditionally before this table existed -- see README's "Known
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
    """5-byte BCD little-endian frequency, per IC-705 CI-V reference p.16."""
    digits = f"{int(freq_hz):010d}"
    pairs = [digits[8:10], digits[6:8], digits[4:6], digits[2:4], digits[0:2]]
    return bytes(bcd_byte(int(p[0]), int(p[1])) for p in pairs)


def encode_offset(offset_hz: float) -> bytes:
    """3-byte BCD duplex offset, 100 Hz resolution (per IC-705 CI-V ref p.16)."""
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


class IC705:
    def __init__(self):
        self.ser = Serial(PORT, BAUD, timeout=1)

    def close(self):
        self.ser.close()

    def send(self, command: bytes, data: bytes = b"") -> bytes:
        frame = b"\xfe\xfe" + TRANSCEIVER_ADDR + CONTROLLER_ADDR + command + data + b"\xfd"
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

    def select_memory(self, group: int, channel: int):
        self.send(b"\x08\xA0", encode_bcd(group))
        self.send(b"\x08", encode_bcd(channel))

    def memory_write(self):
        self.send(b"\x09")

    def read_memory_content(self, group: int, channel: int) -> bytes:
        data = encode_bcd(group) + encode_bcd(channel)
        reply = self.send(b"\x1A\x00", data)
        return reply[6:-1]  # strip FE FE dst src 1A 00 ... FD

    def write_memory_content(self, payload: bytes):
        self.send(b"\x1A\x00", payload)

    def program_channel(self, group: int, channel: int, rx_hz: int, tx_hz: int, mode: str, tone_mode: str, ctcss, name: str):
        self.select_vfo_a()
        self.set_frequency(rx_hz)
        self.set_mode(mode)
        if tx_hz == rx_hz:
            self.set_duplex("simplex")
        else:
            self.set_duplex("+" if tx_hz > rx_hz else "-")
            self.set_offset(abs(tx_hz - rx_hz))
        if tone_mode == "TONE" and ctcss:
            self.set_tone_type(True)
            self.set_tone_freq(float(ctcss))
        else:
            self.set_tone_type(False)
        self.select_memory(group, channel)
        self.memory_write()
        time.sleep(0.1)
        payload = bytearray(self.read_memory_content(group, channel))
        payload[-16:] = encode_name(name)
        self.write_memory_content(bytes(payload))


def load_channels():
    with open(os.path.join(HERE, "sections.json")) as f:
        sections = json.load(f)
    rows = []
    for path in sorted(glob.glob(f"{HERE}/*.csv")):
        section_key = os.path.basename(path).removesuffix(".csv")
        if section_key not in sections:
            print(f"WARNING: {path} has no entry in sections.json -- skipping")
            continue
        meta = sections[section_key]
        group, base = meta["group"], meta["base_channel"]
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
    rows = load_channels()
    radio = IC705()
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
