#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Build the TWRP report ZIP. Usage: build-zip.py OUT.zip [--wifi-2.4]
With --wifi-2.4 it first sets the saved Wi-Fi networks to 2.4 GHz (the wifi24 step), then copies the report:
one ZIP for one TWRP visit ("S6-WiFi-Fix-and-Report.zip")."""
import sys, zipfile, pathlib
here = pathlib.Path(__file__).parent
args = [a for a in sys.argv[1:] if not a.startswith("--")]
out = args[0] if args else "S6Migrate-REPORT.zip"
ub = (here / "update-binary").read_text()
if "--wifi-2.4" in sys.argv:
    w = (here.parent / "wifi24" / "update-binary.in").read_text()
    step = w[w.index("n=0\nfor c in"):w.index('ui " "; ui "Done ($n network(s))')]
    marker = 'STAMP=$(date'
    assert marker in ub
    ub = ub.replace(marker, 'BAND=bg\nui "Wi-Fi: 2.4 GHz for the saved networks (passwords untouched)"\n' + step + marker, 1)
    ub = ub.replace('ui "S6 Migrate: take the reports off the tablet"', 'ui "S6 Migrate: Wi-Fi fix and report"', 1)
    ub = ub.replace('ui " "; ui "Fedora was not changed. Reboot to System."', 'ui " "; ui "Wi-Fi set to 2.4 GHz; nothing else in Fedora was changed. Reboot to System."', 1)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    i = zipfile.ZipInfo("META-INF/com/google/android/update-binary"); i.external_attr = 0o755 << 16; i.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(i, ub)
    z.writestr("META-INF/com/google/android/updater-script", "# S6 Migrate report: the work is done by update-binary\n")
print(out)
