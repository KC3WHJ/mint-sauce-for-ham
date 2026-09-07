#!/usr/bin/env python3
"""Builds ic705_channels.json from the per-section CSVs plus sections.json in
this directory. Run this after adding, editing, or removing a CSV or a
sections.json entry -- the channel picker reads ic705_channels.json, not the
CSVs directly."""
import csv
import glob
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))

MANUAL_ONLY = {12, 13, 14, 15, 16}


def main():
    with open(os.path.join(HERE, "sections.json")) as f:
        sections = json.load(f)

    channels = []
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
                channels.append({
                    "channel_number": ch,
                    "name": row["Name"],
                    "section": meta["display_name"],
                    "group": group,
                    "slot": ch - base + 1,
                    "rx_mhz": float(row["Receive Frequency"]),
                    "tx_mhz": float(row["Transmit Frequency"]),
                    "mode": row["Operating Mode"],
                    "tone_mode": row["Tone Mode"],
                    "ctcss": row["CTCSS"] or None,
                    "manual_only": ch in MANUAL_ONLY,
                    "rx_only": "RX ONLY" in (row.get("Comment") or ""),
                })
    channels.sort(key=lambda c: c["channel_number"])
    out_path = os.path.join(HERE, "ic705_channels.json")
    with open(out_path, "w") as f:
        json.dump(channels, f, indent=2)
    print(f"Wrote {len(channels)} channels to {out_path}")


if __name__ == "__main__":
    main()
