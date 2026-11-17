#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-only
"""S6 Looks: layout, style, keyboard, touch and size, start-up and files: how the tablet looks and feels."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from s6ui import main  # noqa: E402

main("looks", "Looks.qml")
