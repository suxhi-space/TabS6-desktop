#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Build S6Migrate-WIFI-2.4.zip and S6Migrate-WIFI-AUTO.zip (run from TWRP). Usage: build-zip.py OUTDIR"""
import sys, zipfile, pathlib
here = pathlib.Path(__file__).parent
out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
src = (here / "update-binary.in").read_text()
for name, band in (("S6Migrate-WIFI-2.4.zip", "bg"), ("S6Migrate-WIFI-AUTO.zip", "")):
    with zipfile.ZipFile(out / name, "w", zipfile.ZIP_DEFLATED) as z:
        i = zipfile.ZipInfo("META-INF/com/google/android/update-binary"); i.external_attr = 0o755 << 16; i.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(i, src.replace("@BAND@", band))
        z.writestr("META-INF/com/google/android/updater-script", "# S6 Migrate Wi-Fi band: the work is done by update-binary\n")
    print(out / name)
