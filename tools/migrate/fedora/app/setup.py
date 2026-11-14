#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-only
"""S6 Setup: the first start of Fedora on the Galaxy Tab S6, before any desktop.

Runs full screen in the temporary "s6setup" account that the switch prepared: Wi-Fi, your account,
your tablet's settings (filled in from Android), moving your stuff in, then hands over to your own account.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from s6ui import main  # noqa: E402

main("setup", "Setup.qml")
