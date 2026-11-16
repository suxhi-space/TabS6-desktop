#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Build S6Migrate-REPORT.zip (run from TWRP: Install). Usage: build-zip.py OUT.zip"""
import sys, zipfile, pathlib
here = pathlib.Path(__file__).parent
out = sys.argv[1] if len(sys.argv) > 1 else "S6Migrate-REPORT.zip"
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    i = zipfile.ZipInfo("META-INF/com/google/android/update-binary"); i.external_attr = 0o755 << 16; i.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(i, (here / "update-binary").read_text())
    z.writestr("META-INF/com/google/android/updater-script", "# S6 Migrate report: the work is done by update-binary\n")
print(out)
