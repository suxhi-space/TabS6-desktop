#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Build S6Migrate-UPDATE.zip (run from TWRP: Install) for a working Fedora. Usage: build-zip.py OUT.zip"""
import sys, pathlib
here = pathlib.Path(__file__).parent
sys.path.insert(0, str(here.parent / "fix"))
import importlib.util
spec = importlib.util.spec_from_file_location("fixbuild", here.parent / "fix" / "build-zip.py")
fb = importlib.util.module_from_spec(spec); spec.loader.exec_module(fb)
print(fb.build(here / "update-binary", sys.argv[1] if len(sys.argv) > 1 else "S6Migrate-UPDATE.zip", "S6 Migrate update"))
