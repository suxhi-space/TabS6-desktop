#!/usr/bin/env python3
"""Render S6 Setup / S6 Companion pages offscreen in mock mode and save PNGs (for review on a computer).
usage: shoot.py setup|companion|looks OUTDIR [WIDTHxHEIGHT] [light|dark]"""
import os, sys, time
from pathlib import Path
here = Path(__file__).resolve().parent
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ["S6_MOCK"] = "1"
os.environ.setdefault("S6_SHARE", str(here.parent.parent.parent.parent / "android/app/src/main/fontassets"))
sys.path.insert(0, str(here.parent / "app"))
import s6ui
from PySide6.QtCore import QCoreApplication, QEventLoop, QTimer

mode, out = sys.argv[1], Path(sys.argv[2])
size = (sys.argv[3] if len(sys.argv) > 3 else "1280x800").split("x")
theme = sys.argv[4] if len(sys.argv) > 4 else ""
out.mkdir(parents=True, exist_ok=True)
app, engine = s6ui.build(mode, {"setup": "Setup.qml", "looks": "Looks.qml"}.get(mode, "Companion.qml"))
import shiboken6
from PySide6.QtQuick import QQuickWindow
win = shiboken6.wrapInstance(shiboken6.getCppPointer(engine.rootObjects()[0])[0], QQuickWindow)
win.setWidth(int(size[0])); win.setHeight(int(size[1]))

def wait(ms):
    end = time.time() + ms / 1000
    while time.time() < end:
        app.processEvents(QEventLoop.AllEvents, 50)

def snap(name):
    wait(400)
    img = win.grabWindow()
    img.save(str(out / f"{name}.png"))
    print("saved", out / f"{name}.png")

wait(800)
theme_obj = None
if theme:
    win.setProperty("dark", theme == "dark")
if mode == "setup":
    win.setProperty("fullName", "Alex Doe"); win.setProperty("userName", "alex")
    for i, name in enumerate(["1-welcome", "2-wifi", "3-account", "4-tablet", "5-look", "6-moving", "7-done"]):
        win.setProperty("page", i)
        wait(4000 if i in (1, 5) else 700)
        snap(name)
else:
    pages = int(win.property("pageCount") or 6)
    for i in range(pages):
        win.setProperty("page", i)
        wait(1200)
        snap(f"{i+1}-page")
