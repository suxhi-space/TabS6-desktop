#!/usr/bin/env python3
"""Render the five layout previews to PNG (used as Global Theme preview pictures). usage: previews.py OUTDIR"""
import os, sys, time
from pathlib import Path
here = Path(__file__).resolve().parent
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
import shiboken6
app = QGuiApplication(sys.argv)
out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
for lay in ["touch", "centered", "traditional", "topdock", "plasma"]:
    eng = QQmlApplicationEngine()
    eng.rootContext().setContextProperty("hasRedHat", False)
    eng.addImportPath(str(here.parent / "app/qml"))
    eng.loadData(f'''import QtQuick
import "file://{here.parent / "app/qml"}"
Window {{ width: 480; height: 270; visible: true; color: "white"
  LayoutPreview {{ anchors.fill: parent; layout: "{lay}"; effects: "soft"; radius: 0 }} }}'''.encode())
    w = shiboken6.wrapInstance(shiboken6.getCppPointer(eng.rootObjects()[0])[0], QQuickWindow)
    end = time.time() + 0.6
    while time.time() < end: app.processEvents()
    w.grabWindow().save(str(out / f"{lay}.png")); print("saved", lay)
