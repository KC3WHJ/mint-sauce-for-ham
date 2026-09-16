#!/usr/bin/env python3
"""Exports a channels_*.json file (see build_channel_index.py) into the CSV
format the Lab599 TRX Remote Android app imports for the TX-500/TX-500 MP:

    Channel,Name,Frequency,Mode,Filter,Power,ToneMode,ToneFreq,Offset

Channel Picker's own channel data has no Filter or Power concept at all
(those are TX-500-specific), so this fills in a default per channel:
FIL2 for CW (narrower filter, common convention), FIL1 otherwise; a flat
10W for Power on every channel. Both are meant to be starting points -
adjust per-channel in the app afterward if a specific channel needs
something else.

Usage: python3 export_tx500mp_csv.py channels_ic7300.json tx500mp_channels.csv
"""
import csv
import json
import sys

DEFAULT_POWER = "10W"
DEFAULT_TONE_FREQ = 88.5


def convert(channels: list[dict]) -> list[dict]:
    rows = []
    for i, ch in enumerate(channels, start=1):
        mode = ch["mode"]
        filt = "FIL2" if mode == "CW" else "FIL1"
        tone_mode = "Tone" if ch["tone_mode"] not in (None, "OFF") else "None"
        tone_freq = ch["ctcss"] if ch.get("ctcss") else DEFAULT_TONE_FREQ
        offset = round(ch["tx_mhz"] - ch["rx_mhz"], 6)
        rows.append({
            "Channel": i,
            "Name": ch["name"],
            "Frequency": f"{ch['rx_mhz']:.6f}",
            "Mode": mode,
            "Filter": filt,
            "Power": DEFAULT_POWER,
            "ToneMode": tone_mode,
            "ToneFreq": tone_freq,
            "Offset": f"{offset:.6f}",
        })
    return rows


def main():
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <channels_*.json> <output.csv>")
        sys.exit(1)
    src_path, out_path = sys.argv[1], sys.argv[2]

    with open(src_path) as f:
        channels = json.load(f)

    rows = convert(channels)

    with open(out_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "Channel", "Name", "Frequency", "Mode", "Filter",
            "Power", "ToneMode", "ToneFreq", "Offset",
        ])
        writer.writeheader()
        writer.writerows(rows)

    modes = sorted(set(r["Mode"] for r in rows))
    print(f"Wrote {len(rows)} channels to {out_path}.")
    print(f"Modes present: {', '.join(modes)} - TX-500 MP also supports DIG, "
          "not used here since this source data stores digital nets at their "
          "underlying USB/LSB carrier frequency (see channel_maps' own notes).")
    print(f"Filter: FIL2 for CW, FIL1 otherwise. Power: flat {DEFAULT_POWER} "
          "for every channel - both are defaults, not measured/confirmed "
          "values, adjust per-channel in the app if needed.")


if __name__ == "__main__":
    main()
