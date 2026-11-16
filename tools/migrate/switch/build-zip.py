#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Build a TWRP switch ZIP from the repo (what the Android app makes), for tablets that can't run the app any more.
usage: build-zip.py rehearsal|switch OUT.zip [TIMEZONE LANGUAGE "DEVICE NAME"]
On a tablet that already runs Fedora, the switch reinstalls it fresh (using the original Android boot image from
an android-backup-* folder on the drive). Needs the Fedora download and the package on the card or USB drive."""
import sys, zipfile, pathlib, importlib.util
here = pathlib.Path(__file__).parent
spec = importlib.util.spec_from_file_location("bp", here / "build-payload.py"); bp = importlib.util.module_from_spec(spec); spec.loader.exec_module(bp)
mode, out = sys.argv[1], sys.argv[2]
ub = bp.build(mode, *sys.argv[3:6])
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    i = zipfile.ZipInfo("META-INF/com/google/android/update-binary"); i.external_attr = 0o755 << 16; i.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(i, ub)
    z.writestr("META-INF/com/google/android/updater-script", "# S6 Migrate: the work is done by update-binary\n")
    if mode == "rehearsal":
        z.writestr("s6migrate/REHEARSAL", "checks only, nothing is erased\n")
print(out)
