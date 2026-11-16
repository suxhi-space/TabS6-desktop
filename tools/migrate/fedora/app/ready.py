#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-only
"""Getting your tablet ready: the screen shown while S6 Migrate updates Fedora before the login screen.

s6-maint starts it straight on the display (no desktop is running yet) and keeps writing its log; this follows the
log and shows a progress bar, like a phone or a Mac installing an update. "Show details" opens the live terminal
output. If it can't start, the same text stays on the console, as before.

    ready.py LOG [OFFSET]      follow LOG from byte OFFSET
    S6_MOCK=1 ready.py         a simulated run (for screenshots)
"""
import os
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from PySide6.QtCore import QObject, QTimer, QUrl, Property, Signal, Slot  # noqa: E402
from PySide6.QtGui import QFont, QGuiApplication, QImageReader  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402
import s6ui  # noqa: E402

HERE = Path(__file__).resolve().parent
MOCK = os.environ.get("S6_MOCK") == "1"

# s6-maint's headlines ("== date time text"): which job is running
JOBS = [("repair", re.compile(r"^Repair \d/4|^Downloading packages to reinstall")),
        ("update", re.compile(r"^Updating Fedora|^Downloading updates")),
        ("linuxapps", re.compile(r"^Installing the Linux versions")),
        ("extras", re.compile(r"^Adding Better Blur|^Downloading (kwin-effects|darkly|Papirus)")),
        ("codecs", re.compile(r"^Adding media codecs")),
        ("cosmicfiles", re.compile(r"^Adding COSMIC Files|^Downloading COSMIC Files"))]
NAMES = {"repair": "Repairing Fedora", "update": "Updating Fedora", "linuxapps": "Installing your Linux apps",
         "extras": "Adding blur, window style, icons and font", "codecs": "Adding media codecs", "cosmicfiles": "Adding COSMIC Files"}
COUNTER = re.compile(r"^\[\s*(\d+)/(\d+)\]\s*(.*)")
INSTALLING = re.compile(r"\b(Installing|Upgrading|Reinstalling|Removing|Cleanup|Verifying|Running scriptlet|Downgrading)\b", re.I)
FINAL = re.compile(r"^(All done|Not finished this time|No internet)")


class Follower(QObject):
    changed = Signal()
    line = Signal(str)

    def __init__(self, path, offset):
        super().__init__()
        self.path, self.pos = path, offset
        self.jobs, self.job = [], ""
        self.title, self.detail = "Getting your tablet ready", "Starting..."
        self.frac, self.overall, self.final, self.minutes = 0.0, 0.0, "", 0
        self.installing = False
        self.t0 = time.monotonic()   # not the wall clock: s6-maint corrects the clock from the internet
        self._buf = b""
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.poll)
        self.timer.start(400)

    # ---- properties for the QML page
    @Property(str, notify=changed)
    def jobLabel(self):
        return self.detail

    @Property(float, notify=changed)
    def progress(self):
        return self.overall

    @Property(str, notify=changed)
    def finishedText(self):
        return self.final

    @Property(str, notify=changed)
    def stepLabel(self):
        if not self.job:
            return ""
        n = len(self.jobs) or 1
        i = self.jobs.index(self.job) + 1 if self.job in self.jobs else 1
        return (f"Step {i} of {n} · " if n > 1 else "") + NAMES.get(self.job, "")

    @Property(str, notify=changed)
    def elapsed(self):
        m = int((time.monotonic() - self.t0) // 60)
        return "" if m < 1 else (f"{m} min so far" if m < 60 else f"{m // 60} h {m % 60} min so far")

    @Slot(result=str)
    def wallpaper(self):
        """The new account's wallpaper (from Android), or Fedora's; shown blurred."""
        ok = {bytes(f).decode() for f in QImageReader.supportedImageFormats()}
        homes = sorted(Path("/home").glob("*/.local/share/wallpapers/S6Migrate/android-home.*"),
                       key=lambda f: f.stat().st_mtime, reverse=True) if not MOCK else []
        for f in homes:
            if f.suffix[1:].lower() in ok:
                return QUrl.fromLocalFile(str(f)).toString()
        if MOCK and os.environ.get("S6_MOCK_ANDROID_WALL"):
            return QUrl.fromLocalFile(os.environ["S6_MOCK_ANDROID_WALL"]).toString()
        import json
        return json.loads(s6ui.Backend("setup").wallpapers()).get("default", "")

    # ---- reading the log
    def poll(self):
        try:
            with open(self.path, "rb") as f:
                f.seek(self.pos)
                data = f.read()
                self.pos = f.tell()
        except OSError:
            return
        if not data:
            self.changed.emit()      # the elapsed time
            return
        self._buf += data
        *lines, self._buf = re.split(rb"[\r\n]", self._buf)
        for raw in lines:
            t = raw.decode(errors="replace").rstrip()
            if t:
                self.feed(t)
        self.changed.emit()

    def feed(self, t):
        self.line.emit(t)
        if t.startswith("== "):
            msg = re.sub(r"^== \d{4}-\d\d-\d\d \d\d:\d\d:\d\d ", "", t)
            m = re.search(r"before the login screen: (.*)$", msg)
            if m:
                self.jobs = m.group(1).split()
                return
            for job, rx in JOBS:
                if rx.search(msg):
                    if job != self.job:
                        self.job, self.frac, self.installing = job, 0.0, False
                    break
            if FINAL.search(msg):
                self.final = msg
                self.overall = 1.0 if msg.startswith("All done") else self.overall
                self.detail = msg
                QTimer.singleShot(4000, QGuiApplication.quit)
                return
            self.detail = re.sub(r"\.\.\.$", "", msg)
            if msg.startswith("Downloading") or "(round" in msg:
                self.installing = False          # a new download round starts
            if msg.startswith("Waiting for Wi-Fi"):
                self.detail = "Waiting for Wi-Fi"
            elif re.match(r"Round \d+ stopped", msg):
                self.detail = "Connection dropped · trying again in 30 seconds"
        else:
            if t.startswith("Running transaction"):
                self.installing = True           # dnf moved from downloading to installing
            c = COUNTER.match(t)
            if c:
                n, total, rest = int(c.group(1)), max(1, int(c.group(2))), c.group(3)
                inst = bool(INSTALLING.search(rest)) or self.installing
                self.installing = inst
                # downloading is the first half of a job, installing the second
                self.frac = (0.5 if inst else 0.0) + 0.5 * n / total
                self.detail = ("Installing" if inst else "Downloading") + f" · {n} of {total}"
            else:
                w = re.search(r"still working \((\d+) min\)", t)
                if w:   # dnf's own minutes, so the time shown is right even if this screen started late
                    self.t0 = min(self.t0, time.monotonic() - 60 * int(w.group(1)))
        n = len(self.jobs) or 1
        i = self.jobs.index(self.job) if self.job in self.jobs else 0
        self.overall = max(self.overall, min(0.99, (i + self.frac) / n))


def mock_log(path):
    """A short simulated maintenance run, written over a few seconds."""
    lines = ["", "== 2026-11-16 10:31:02 S6 Migrate is finishing work before the login screen: update linuxapps extras",
             "== 2026-11-16 10:31:02 Keep the tablet plugged in.", "== 2026-11-16 10:31:09 Updating Fedora...",
             "== 2026-11-16 10:31:09 Downloading updates (round 1)...", "Updating and loading repositories:",
             " Fedora 44 - aarch64 - Updates     100% |   2.1 MiB/s |  12.4 MiB |  00m06s", "Repositories loaded.",
             "Transaction Summary:", " Installing:         4 packages", " Upgrading:        537 packages", " Replacing:        537 packages"]
    pk = ["libva-utils-2.23.0-1.fc44", "kf6-kio-6.20.0-1.fc44", "plasma-workspace-6.6.3-1.fc44", "kwin-6.6.3-1.fc44",
          "mesa-dri-drivers-26.2.1-1.fc44", "firefox-159.0-1.fc44", "breeze-icon-theme-6.20.0-1.fc44", "glibc-2.42-6.fc44"]
    for i in range(1, 300, 7):
        lines.append(f"[{i:3d}/541] {pk[i % len(pk)]}.aarch64   100% | 612.4 KiB/s |   1.2 MiB |  00m02s")
    lines.append("   ...still working (3 min)")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    if MOCK:
        log = os.environ.get("S6_READY_LOG", "/tmp/s6-ready-mock.log")
        mock_log(log)
        offset = 0
    else:
        log = sys.argv[1] if len(sys.argv) > 1 else "/var/lib/s6migrate/maint.log"
        offset = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    # Before the login screen nothing scales the display (Plasma does that later): on the Tab S6's 2560 x 1600
    # screen everything came out half size. Scale so the short side is about 800 points, like the desktop.
    if "QT_SCALE_FACTOR" not in os.environ and not MOCK:
        for m in sorted(Path("/sys/class/drm").glob("card*-*/modes")):
            try:
                w, h = (int(x) for x in m.read_text().split()[0].split("x"))
            except (OSError, ValueError, IndexError):
                continue
            os.environ["QT_SCALE_FACTOR"] = str(max(1, round(min(w, h) / 800)))
            break
    app = QGuiApplication(sys.argv)
    app.setApplicationName("S6 Migrate")
    fams = s6ui.load_fonts()
    app.setFont(QFont("Red Hat Text" if "Red Hat Text" in fams else "Noto Sans", 11))
    eng = QQmlApplicationEngine()
    fol = Follower(log, offset)
    eng._fol = fol
    eng.rootContext().setContextProperty("maint", fol)
    eng.rootContext().setContextProperty("mock", MOCK)
    eng.rootContext().setContextProperty("hasRedHat", "Red Hat Display" in fams)
    eng.addImportPath(str(HERE / "qml"))
    eng.load(QUrl.fromLocalFile(str(HERE / "qml" / "GettingReady.qml")))
    if not eng.rootObjects():
        sys.exit(1)
    return app, eng


if __name__ == "__main__":
    _app, _eng = main()
    sys.exit(_app.exec())
