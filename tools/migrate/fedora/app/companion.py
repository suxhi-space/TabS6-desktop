#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-only
"""S6 Companion: welcome, finishing up, Android app tools, updates, fixes and tablet tools.

Opens by itself at your first login (to finish bringing your Android apps over), then lives in the menu.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from s6ui import main  # noqa: E402

main("companion", "Companion.qml")
