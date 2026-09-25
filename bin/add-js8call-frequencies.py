#!/usr/bin/env python3
"""Add frequencies to JS8Call's frequency dropdown (a JS8Call profile's .ini file).

JS8Call keeps its selectable frequencies in the profile .ini as a Qt QVariant blob
(FrequenciesForRegionModes_01), written as an escaped string. This tool decodes it, adds the
frequencies you name, and writes it back in exactly the form Qt writes it.

Safety:
  * It REFUSES to write unless its own encoder reproduces the file's EXISTING value byte for
    byte (proof that what it writes is what Qt would write).
  * Frequencies already in the list are skipped; if there's nothing to add it changes nothing.
  * Before changing a file it saves a timestamped copy next to it (<file>.pre-freqs-YYYYmmdd-HHMM).
  * Close JS8Call first - it rewrites its settings when it exits and would undo the change.

Usage:
  add-js8call-frequencies.py INI FREQ_HZ [FREQ_HZ ...]         # dry run: shows what would change
  add-js8call-frequencies.py INI --apply FREQ_HZ [FREQ_HZ ...]  # actually write it

Exit status: 0 = done or nothing to do; 1 = refused / unsafe / no table in that profile yet.

Used by Setup_Ham_Radio_Stack.sh to add AmRRON's JS8Call frequencies (3.588, 7.110, 14.110 MHz).
"""
import os
import re
import shutil
import struct
import sys
import time

KEY = "FrequenciesForRegionModes_01"
SHORT = {7: r'\a', 8: r'\b', 9: r'\t', 10: r'\n', 11: r'\v', 12: r'\f', 13: r'\r'}
SHORT_R = {'a': 7, 'b': 8, 't': 9, 'n': 10, 'v': 11, 'f': 12, 'r': 13, '\\': 92, '"': 34}


def unescape(s):
    out = bytearray()
    i = 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            if n == 'x':
                m = re.match(r'[0-9a-fA-F]{1,2}', s[i + 2:])
                out.append(int(m.group(0), 16))
                i += 2 + len(m.group(0))
                continue
            if n == '0':
                out.append(0)
                i += 2
                continue
            if n in SHORT_R:
                out.append(SHORT_R[n])
                i += 2
                continue
        out += c.encode('latin-1', 'replace')
        i += 1
    return bytes(out)


def escape(b):
    """Mimic Qt's QSettings ini escaping, as observed in real JS8Call files."""
    out = []
    prev = None  # None | 'nul' | 'hex' | 'lit' | 'short'
    for x in b:
        ch = chr(x)
        if x == 0:
            out.append(r'\0')
            prev = 'nul'
        elif x in SHORT:
            out.append(SHORT[x])
            prev = 'short'
        elif x == 92:
            out.append('\\\\')
            prev = 'lit'
        elif x == 34:
            out.append('\\"')
            prev = 'lit'
        elif 0x20 <= x <= 0x7e:
            # a digit / hex digit right after a \0 or \x escape would be swallowed by it: escape it too
            if prev in ('nul', 'hex') and re.match(r'[0-9a-fA-F]', ch):
                out.append('\\x%02x' % x)
                prev = 'hex'
            else:
                out.append(ch)
                prev = 'lit'
        else:
            out.append('\\x%x' % x)
            prev = 'hex'
    return ''.join(out)


def parse(blob):
    hdr_end = blob.index(b'FrequencyItems') + len(b'FrequencyItems')
    p = hdr_end + 1                                   # the NUL after the type name
    (count,) = struct.unpack('>I', blob[p:p + 4])
    p += 4
    items = []
    for _ in range(count):
        (freq,) = struct.unpack('>Q', blob[p:p + 8])
        p += 8
        parts = []
        for _ in range(2):                            # mode, region: 4-byte length + bytes
            (n,) = struct.unpack('>I', blob[p:p + 4])
            p += 4
            parts.append(blob[p:p + n])
            p += n
        items.append((freq, parts[0], parts[1]))
    return blob[:hdr_end + 1], items, blob[p:]


def build(head, items, tail):
    out = bytearray(head) + struct.pack('>I', len(items))
    for freq, mode, region in items:
        out += struct.pack('>Q', freq)
        for part in (mode, region):
            out += struct.pack('>I', len(part)) + part
    return bytes(out) + tail


def main(argv):
    args = argv[1:]
    apply = '--apply' in args
    args = [a for a in args if a != '--apply']
    if len(args) < 2:
        print(__doc__)
        return 1
    ini = os.path.expanduser(args[0])
    specs = args[1:]
    if not os.path.isfile(ini):
        print(f"{ini} doesn't exist yet - run JS8Call once, close it, then re-run.")
        return 1
    text = open(ini, encoding='utf-8', errors='surrogateescape').read()
    m = re.search(r'^' + KEY + r'=(.*)$', text, re.M)
    if not m:
        print("This profile has no stored frequency table yet (JS8Call writes it the first time it "
              "exits) - run JS8Call once, close it, then re-run.")
        return 1
    raw = m.group(1)
    try:
        blob = unescape(raw)
        head, items, tail = parse(blob)
        safe = build(head, items, tail) == blob and escape(blob) == raw
    except Exception as e:  # unexpected format
        print(f"Couldn't decode the frequency table ({e}) - leaving the file alone.")
        return 1
    if not safe:
        print("REFUSING: my encoder doesn't reproduce this file's existing value exactly, so it "
              "isn't safe to edit. Add the frequencies in JS8Call's own Settings > Frequency page.")
        return 1

    have = {f for f, _, _ in items}
    added = []
    for spec in specs:
        hz = int(spec.split(':')[0])
        if hz in have:
            continue
        items.append((hz, b'JS8\0', b'ALL\0'))
        have.add(hz)
        added.append(hz)
    if not added:
        print("All of those frequencies are already in the list - nothing to do.")
        return 0
    items.sort(key=lambda t: t[0])
    new_raw = escape(build(head, items, tail))
    _, back, _ = parse(unescape(new_raw))
    if [i[0] for i in back] != [i[0] for i in items]:
        print("Internal check failed (read-back mismatch) - leaving the file alone.")
        return 1
    print("Adding: " + ", ".join("%.3f MHz" % (f / 1e6) for f in sorted(added)))
    print("List will be: " + ", ".join("%.3f" % (f / 1e6) for f, _, _ in items))
    if not apply:
        print("(dry run - nothing written; add --apply to write)")
        return 0

    backup = f"{ini}.pre-freqs-{time.strftime('%Y%m%d-%H%M')}"
    shutil.copy2(ini, backup)
    open(ini, 'w', encoding='utf-8', errors='surrogateescape').write(text[:m.start(1)] + new_raw + text[m.end(1):])
    print(f"Written. (Backup: {backup})")
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
