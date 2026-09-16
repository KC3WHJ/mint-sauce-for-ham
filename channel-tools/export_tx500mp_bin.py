#!/usr/bin/env python3
"""Exports a channels_*.json file (see build_channel_index.py) into the
binary .mem format used by Lab599's TRX Mem desktop software (running
under Wine here) for the TX-500/TX-500 MP.

Format reverse-engineered live 2026-09-16 from a real template.mem plus
two more saves with known field changes (see channel-tools/README.md for
the full writeup) - not guessed from a blank template alone:

    600 bytes total = 100 fixed-size 6-byte records (channel 1..100,
    position in the file IS the channel number - nothing stores it
    explicitly).

    Per record:
      bytes 0-3: frequency in Hz, little-endian uint32
      byte  4:   mode, single ASCII digit (confirmed: 0=unset/blank (NOT a
                 real mode - a fresh/never-touched channel defaults to 0
                 and its dropdown just shows "USB" as a UI default without
                 that reflecting a real saved value), 1=LSB, 2=USB
                 (confirmed via an explicit re-select, not the misleading
                 0 default), 5=AM. CW/FM/DIG not confirmed, this script
                 refuses them rather than guess.
      byte  5:   PreATT, single ASCII digit (confirmed: "0" = off; this
                 script always writes "0" since Channel Picker's channel
                 data has no preamp/attenuator concept to map from)

This format has NO room for a channel name (or filter/power/tone/offset,
which the CSV/TRX Remote Android app format - export_tx500mp_csv.py -
does support) - only frequency, mode, and PreATT per channel. Channel
numbers here are positional and don't need to (and can't) carry a name;
cross-reference the channel number against Channel Picker or the CSV
export to know what's programmed where.

Usage: python3 export_tx500mp_bin.py channels_ic7300.json tx500mp_channels.mem
"""
import json
import struct
import sys

RECORD_COUNT = 100
RECORD_SIZE = 6
BLANK_RECORD = b"\x00\x00\x00\x00" + b"00"

MODE_CODES = {"LSB": b"1", "USB": b"2", "AM": b"5"}


def convert(channels: list[dict]) -> bytes:
    if len(channels) > RECORD_COUNT:
        raise ValueError(
            f"{len(channels)} channels won't fit - this format only has "
            f"{RECORD_COUNT} memory slots."
        )

    records = [bytearray(BLANK_RECORD) for _ in range(RECORD_COUNT)]
    for i, ch in enumerate(channels):
        mode = ch["mode"]
        if mode not in MODE_CODES:
            raise ValueError(
                f"Channel {i + 1} ({ch['name']!r}) uses mode {mode!r}, which "
                "hasn't been confirmed against real Lab599 TRX Mem output "
                "yet (only USB/LSB/AM have been verified) - refusing to "
                "guess an encoding for it. Save a test channel in that mode "
                "from the Lab599 software and diff it against a known "
                "record to confirm its code before adding it here."
            )
        freq_hz = round(ch["rx_mhz"] * 1_000_000)
        records[i][0:4] = struct.pack("<I", freq_hz)
        records[i][4:5] = MODE_CODES[mode]
        # byte 5 (PreATT) stays "0" - no source field to map from.

    return b"".join(bytes(r) for r in records)


def main():
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <channels_*.json> <output.mem>")
        sys.exit(1)
    src_path, out_path = sys.argv[1], sys.argv[2]

    with open(src_path) as f:
        channels = json.load(f)

    data = convert(channels)

    with open(out_path, "wb") as f:
        f.write(data)

    print(f"Wrote {len(channels)} channels ({len(data)} bytes) to {out_path}.")
    print(f"Channel numbers are positional (1-{len(channels)}) - no name is "
          "stored in this format. Cross-reference against Channel Picker "
          "or the CSV export to know what's programmed at each number.")


if __name__ == "__main__":
    main()
