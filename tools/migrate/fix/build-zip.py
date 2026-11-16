#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Build S6Migrate-FIX.zip (run from TWRP: Install). Usage: build-zip.py OUT.zip"""
import sys, zipfile, pathlib
here = pathlib.Path(__file__).parent
out = sys.argv[1] if len(sys.argv) > 1 else "S6Migrate-FIX.zip"
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    i = zipfile.ZipInfo("META-INF/com/google/android/update-binary"); i.external_attr = 0o755 << 16; i.compress_type = zipfile.ZIP_DEFLATED
    ub = (here / "update-binary").read_text()
    py = (here / "s6pamtest.py").read_text()
    assert "EOPY" not in py and "# @PAMTEST@" in ub
    fed = here.parent / "fedora" / "system"
    sc, mt = (fed / "s6-selfcheck").read_text(), (fed / "s6-maint").read_text()
    assert "EOSC" not in sc and "EOMT" not in mt and "# @S6SELFCHECK@" in ub and "# @S6MAINT@" in ub
    ub = ub.replace("# @PAMTEST@\n", py).replace("# @S6SELFCHECK@\n", sc).replace("# @S6MAINT@\n", mt)
    z.writestr(i, ub)
    z.writestr("META-INF/com/google/android/updater-script", "# S6 Migrate fix: the work is done by update-binary\n")
print(out)
