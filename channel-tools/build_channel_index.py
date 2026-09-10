#!/usr/bin/env python3
"""Builds channels_<radio>.json from the per-section CSVs plus each radio's
map in channel_maps/. Run this after adding, editing, or removing a CSV or a
channel_maps/*.json entry -- the channel picker reads channels_<radio>.json,
not the CSVs directly.

One map per radio, since not every radio can hold every section: an
HF-only rig like the IC-7300 only gets the non-VHF/UHF sections, while a
multi-band rig like the IC-705 gets all of them. See README.md."""
import csv
import glob
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
MAPS_DIR = os.path.join(HERE, "channel_maps")

# ISS crossband channels: RX/TX are on completely different bands, not
# representable via CI-V's duplex-offset mechanism -- manual-only on any
# radio. Harmless to leave global: no other section reuses these numbers.
MANUAL_ONLY = {12, 13, 14, 15, 16}


def build_one(radio_key: str, sections: dict):
    channels = []
    for path in sorted(glob.glob(f"{HERE}/*.csv")):
        section_key = os.path.basename(path).removesuffix(".csv")
        if section_key not in sections:
            continue
        meta = sections[section_key]
        group, base = meta.get("group"), meta["base_channel"]
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
    out_path = os.path.join(HERE, f"channels_{radio_key}.json")
    with open(out_path, "w") as f:
        json.dump(channels, f, indent=2)
    print(f"{radio_key}: wrote {len(channels)} channels to {os.path.basename(out_path)}")


def main():
    map_paths = sorted(glob.glob(f"{MAPS_DIR}/*.json"))
    if not map_paths:
        print(f"No radio maps found in {MAPS_DIR}/ -- nothing to build.")
        return
    for path in map_paths:
        radio_key = os.path.basename(path).removesuffix(".json")
        with open(path) as f:
            sections = json.load(f)
        build_one(radio_key, sections)


if __name__ == "__main__":
    main()
