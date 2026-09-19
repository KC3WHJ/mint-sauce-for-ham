# AmRRON custom HTML forms for Flmsg

The official AmRRON custom Flmsg forms, **V5.0 set (updated 27 Nov 2024)**, exactly as AmRRON
distributes them. Source and current versions: <https://amrron.com/amrron-forms/>
(how to download and install: <https://amrron.com/downloading-custom-forms/>).
AmRRON's own release notes are in `AmRRON Custom html Forms README.txt`.
These files are AmRRON's work, bundled here unmodified only so a rebuilt
station has them; check the source above for newer versions.

| File | Form |
|---|---|
| `amrron_statrep_V5.1.html` | STATREP (current, added 27 Nov 2024) |
| `amrron_statrep_V5.00.html` | STATREP V5.00 (obsolete after 1 Jan 2025; kept to read old traffic) |
| `amrron_sitrep_V5.00.html` | SITREP |
| `amrron_spotrep_V5.00.html` | SPOTREP |
| `amrron_blank_Form_V5.00.html` | Blank form (AIB, EXSUM, welfare, party-to-party, schedules...) |

AmRRON asks members to keep the previous versions in their `CUSTOM` folder
so traffic from stations that haven't updated can still be opened.

## How they get installed here

Flmsg only offers custom forms that sit in the `CUSTOM` folder of its data
directory. `bin/install-amrron-forms.sh` copies these files there (never
overwriting a file already present) for each Flmsg on this station:

- the radio-connected Flmsg: `~/.nbems/CUSTOM` - done by `Start_Fldigi.sh`
  and `Start_Flmsg.sh`
- the receive-only WebSDR Flmsg: `~/Fldigi-WebSDR/.nbems/CUSTOM` - done by
  `Start_Fldigi_WebSDR.sh`

`Setup_Ham_Radio_Stack.sh` puts the bundle at `~/.local/share/amrron-forms/`
for those scripts to read. To add a newer AmRRON form set, drop the files in
this folder and re-run the setup script (or copy them into each `CUSTOM`
folder by hand).
