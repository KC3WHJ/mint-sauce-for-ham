#!/usr/bin/env python3
"""Best-effort extractor for RAINWorks-style "Standalone Analog Programming
Guide" PDFs -> per-section CSVs + channel_maps/ic705.json for this toolkit.

This is tuned to the specific table layout RAINWorks uses (two row formats:
a "Fixed Base Bank" table with BW/Tone/TX-Off columns, and a "Local/Extended"
table with a ZIP column). A differently-formatted PDF will likely need
adjustments to the regexes below -- ALWAYS spot-check the output CSVs against
the source PDF before programming a radio from them.

Usage:
    python3 extract_pdf.py "/path/to/Some Programming Guide.pdf" [output_dir]
"""
import csv
import os
import re
import subprocess
import sys
import json

FIXED_BASE_HEADER = re.compile(r"^Fixed Base Bank - CH(\d+)-(\d+)$")
LOCAL_ADDON_HEADER = re.compile(r"^Local Add-ons - (\d{5}) / (.+)$")
EXTENDED_HEADER = re.compile(r"^(\d{5}) - (Extended .+)$")

# "1             CALL52        146.52000          146.52000        25K              Off              No            Amateur simplex"
FIXED_ROW = re.compile(
    r"^\s*(?P<ch>\d+)\s+(?P<name>\S+)\s+(?P<rx>[\d.]+)\s+(?P<tx>[\d.]+)\s+"
    r"(?P<bw>\S+)\s+(?P<tone>\S+)\s+(?P<txoff>Yes|No)\s*"
)

# "58                 W3SK               146.7900             146.1900              131.8                 19114"
LOCAL_ROW = re.compile(
    r"^\s*(?P<ch>\d+)\s+(?P<name>\S+)\s+(?P<rx>[\d.]+)\s+(?P<tx>[\d.]+)\s+"
    r"(?P<tone>\S+)\s+(?P<zip>\d{5})\s*"
)

CSV_HEADER = ["Channel Number", "Receive Frequency", "Transmit Frequency", "Offset Frequency",
              "Offset Direction", "Operating Mode", "Name", "Tone Mode", "CTCSS", "DCS",
              "DTCS Code", "Transmit Power", "Skip", "Comment"]


def to_row(ch, name, rx, tx, mode, tone, comment=""):
    rx, tx = float(rx), float(tx)
    if rx == tx:
        offset, direction = "", "Simplex"
    else:
        offset, direction = f"{abs(tx - rx):.6f}", ("+" if tx > rx else "-")
    tone_mode = "OFF" if tone.upper() in ("OFF", "CSQ", "") else "TONE"
    ctcss = "" if tone_mode == "OFF" else tone
    return [ch, f"{rx:.6f}", f"{tx:.6f}", offset, direction, mode, name, tone_mode, ctcss,
            "", "", "", "", comment]


def parse(text: str):
    lines = text.splitlines()
    sections = []  # list of dicts: key, display_name, description, rows
    current = None
    mode_kind = None  # "fixed" or "local"
    i = 0
    while i < len(lines):
        line = lines[i]
        m = FIXED_BASE_HEADER.match(line.strip())
        if m:
            lo, hi = int(m.group(1)), int(m.group(2))
            current = {"key": f"Fixed_Base_{len(sections) + 1}", "display_name": f"Fixed Base {len(sections) + 1}",
                       "base": lo, "rows": []}
            # description is the next non-blank line
            desc = lines[i + 1].strip() if i + 1 < len(lines) else ""
            current["description"] = f"{desc} (CH{lo}-{hi})"
            sections.append(current)
            mode_kind = "fixed"
            i += 1
            continue
        m = LOCAL_ADDON_HEADER.match(line.strip())
        if m:
            zip_code, place = m.group(1), m.group(2)
            current = {"key": f"Local_Add-On_{zip_code}", "display_name": f"Local Add-On {zip_code}", "rows": []}
            current["description"] = f"Local ham repeaters near ZIP {zip_code}, {place}"
            sections.append(current)
            mode_kind = "local"
            i += 1
            continue
        m = EXTENDED_HEADER.match(line.strip())
        if m:
            zip_code, label = m.group(1), m.group(2)
            current = {"key": f"Extended_{zip_code}", "display_name": f"Extended Coverage {zip_code}", "rows": []}
            current["description"] = f"{label} (ZIP {zip_code})"
            sections.append(current)
            mode_kind = "local"
            i += 1
            continue
        if current is not None:
            if mode_kind == "fixed":
                fm = FIXED_ROW.match(line)
                if fm:
                    mode = "FM" if fm["bw"].upper().startswith("25") else "FM-N"
                    comment = "RX ONLY - set TX inhibit/Skip Tx in radio" if fm["txoff"] == "Yes" else ""
                    current["rows"].append(to_row(fm["ch"], fm["name"], fm["rx"], fm["tx"], mode, fm["tone"], comment))
            elif mode_kind == "local":
                lm = LOCAL_ROW.match(line)
                if lm:
                    current["rows"].append(to_row(lm["ch"], lm["name"], lm["rx"], lm["tx"], "FM", lm["tone"]))
        i += 1
    return sections


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    pdf_path = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "."
    os.makedirs(out_dir, exist_ok=True)

    text = subprocess.run(["pdftotext", "-layout", pdf_path, "-"], capture_output=True, text=True, check=True).stdout
    sections = parse(text)

    if not sections:
        print("No sections recognized -- this PDF's layout doesn't match the expected RAINWorks format.")
        print("You'll need to adjust the regexes in extract_pdf.py, or build the CSVs by hand using")
        print("wcs705_blank_template.csv as your column reference.")
        sys.exit(1)

    sections_json = {}
    total = 0
    for idx, sec in enumerate(sections):
        csv_path = os.path.join(out_dir, f"{sec['key']}.csv")
        with open(csv_path, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(CSV_HEADER)
            w.writerows(sec["rows"])
        base_channel = sec.get("base") or (int(sec["rows"][0][0]) if sec["rows"] else 1)
        sections_json[sec["key"]] = {
            "display_name": sec["display_name"],
            "description": sec["description"],
            "group": idx,
            "base_channel": base_channel,
        }
        print(f"{sec['key']}: {len(sec['rows'])} channels -> {csv_path}")
        total += len(sec["rows"])

    # RAINWorks guides are VHF/UHF+HF repeater listings -- inherently a
    # grouped-memory (multi-band) radio's territory, so this writes an
    # IC-705-shaped map by default. Merge the new sections into
    # channel_maps/ic705.json (or another grouped radio's map) by hand if
    # you're adding to an existing set rather than starting fresh; this
    # always overwrites.
    maps_dir = os.path.join(out_dir, "channel_maps")
    os.makedirs(maps_dir, exist_ok=True)
    map_path = os.path.join(maps_dir, "ic705.json")
    with open(map_path, "w") as f:
        json.dump(sections_json, f, indent=2)

    print(f"\nExtracted {total} channels across {len(sections)} sections -> {map_path}")
    print("REVIEW THE CSVs before trusting them -- this is a best-effort text-layout parser,")
    print("not a guaranteed-correct PDF table reader. Compare a few rows against the source PDF.")
    print("Then run build_channel_index.py to regenerate channels_ic705.json.")


if __name__ == "__main__":
    main()
