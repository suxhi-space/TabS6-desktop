#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-only
"""Shared engine for S6 Setup (first boot) and S6 Companion (after login).

The windows are Qt Quick (QML) pages; this module gives them a small backend:
  backend.run(id, argv)        start a command; lines arrive as output(id, line), the end as finished(id, code)
  backend.read(path)           read a small text file ("" if missing)
  backend.json(path)           read a JSON file as a string ("{}" if missing)
  backend.env(name)            an environment variable
  backend.which(cmd)           true if a command exists
  backend.packageInfo()        what the Android side packed: settings, Wi-Fi count, parts (JSON string)
Privileged work goes through the root helper: pkexec /usr/local/libexec/s6migrate/s6-helper <action> ...

S6_MOCK=1 runs every command as a short simulation (for screenshots and tests on a computer).
"""
import base64
import json
import os
import subprocess
import re
import shlex
import sys
from pathlib import Path

from PySide6.QtCore import QObject, QProcess, QTimer, QUrl, Signal, Slot, QByteArray, Property
from PySide6.QtGui import QFontDatabase, QGuiApplication, QFont, QIcon
from PySide6.QtQml import QQmlApplicationEngine

HERE = Path(__file__).resolve().parent
SHARE = Path(os.environ.get("S6_SHARE", "/usr/local/share/s6migrate"))
HELPER = os.environ.get("S6_HELPER", "/usr/local/libexec/s6migrate/s6-helper")
STATE = Path(os.environ.get("S6_STATE", "/var/lib/s6migrate"))
MOCK = os.environ.get("S6_MOCK") == "1"
VERSION = "0.4.12"


def load_fonts():
    """Red Hat Display / Text, shipped as base64 text (TWRP can only carry text into Fedora)."""
    fams = {}
    for d in (SHARE / "fonts", HERE / "fonts"):
        if not d.is_dir():
            continue
        for f in sorted(d.iterdir()):
            try:
                if f.suffix == ".b64":
                    data = base64.b64decode(f.read_bytes())
                elif f.suffix == ".ttf":
                    data = f.read_bytes()
                else:
                    continue
            except Exception:
                continue
            fid = QFontDatabase.addApplicationFontFromData(QByteArray(data))
            for fam in QFontDatabase.applicationFontFamilies(fid):
                fams[fam] = True
        if fams:
            break
    return fams


def package_parts():
    """Every part of the newest package this system can see: copied into Fedora, or on a mounted drive."""
    cands = []
    for d in sorted(STATE.glob("package-*")):
        if (d / "plan.txt").is_file():
            cands.append(d)
    for base in [Path("/run/s6migrate")] + [Path(p) for p in (f"/run/media/{os.environ.get('USER', '')}",)]:
        if base.is_dir():
            for m in base.iterdir():
                for d in sorted((m / "S6Migrate").glob("2*")) if (m / "S6Migrate").is_dir() else []:
                    if (d / "plan.txt").is_file():
                        cands.append(d)
    extra = os.environ.get("S6_PACKAGES")  # test hook: space separated folders
    if extra:
        cands += [Path(p) for p in extra.split()]

    def pid(d):
        n = d.name
        m = re.search(r"(\d{8}-\d{6})", n)
        return m.group(1) if m else n

    if not cands:
        return {"id": "", "parts": [], "want": 0}
    newest = max(pid(d) for d in cands)
    parts = [d for d in cands if pid(d) == newest]
    want = 1
    for d in parts:
        t = (d / "parts.txt")
        if t.is_file():
            for line in t.read_text(errors="replace").splitlines():
                if line.startswith("parts="):
                    want = max(want, int(line[6:] or 1))
    return {"id": newest, "parts": [str(p) for p in parts], "want": want}


def read_settings(parts):
    s = {}
    # The region chosen in the app right before installing wins over the Android values in the package.
    reg = STATE / "region.env"
    if reg.is_file():
        r = dict(l.split("=", 1) for l in reg.read_text(errors="replace").splitlines() if "=" in l)
        for k_from, k_to in (("tz", "timezone"), ("lang", "locale"), ("name", "device_name")):
            if r.get(k_from):
                s[k_to] = r[k_from]
    for p in parts:
        f = Path(p) / "settings" / "settings.txt"
        if f.is_file():
            for line in f.read_text(errors="replace").splitlines():
                if "=" in line:
                    k, v = line.split("=", 1)
                    s.setdefault(k, v)
            s["wallpaper"] = (Path(p) / "settings" / "wallpaper").is_file()
    return s


def _hex_seed(theme_json):
    """The seed colour from Android's theme_customization_overlay_packages (Material You / One UI palette)."""
    try:
        t = json.loads(theme_json)
    except (ValueError, TypeError):
        return ""
    if not isinstance(t, dict):        # "null" when Android has no palette set
        return ""
    for k in ("android.theme.customization.system_palette", "android.theme.customization.accent_color"):
        v = str(t.get(k, "")).lstrip("#")
        if re.fullmatch(r"[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8}", v):
            return "#" + v[-6:].upper()
    return ""


def _wallpaper_seed(path):
    """Like Android's wallpaper colours: the most common vivid hue of the picture."""
    from PySide6.QtGui import QImage
    from PySide6.QtCore import Qt
    img = QImage(str(path))
    if img.isNull():
        return ""
    img = img.scaled(48, 48, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
    bins = {}
    for y in range(img.height()):
        for x in range(img.width()):
            c = img.pixelColor(x, y)
            h, s, v = c.hsvHueF(), c.hsvSaturationF(), c.valueF()
            if h < 0 or s < 0.25 or v < 0.25:
                continue
            b = int(h * 24) % 24
            w, r, g, bl, n = bins.get(b, (0, 0, 0, 0, 0))
            bins[b] = (w + s * v, r + c.redF(), g + c.greenF(), bl + c.blueF(), n + 1)
    if not bins:
        return ""
    w, r, g, b, n = max(bins.values())
    return "#%02X%02X%02X" % (int(255 * r / n), int(255 * g / n), int(255 * b / n))


def accent_palette(seed):
    """Accent tokens for light and dark from one seed colour, kept readable (white text on the light accent)."""
    import colorsys
    if not seed:
        return None
    r, g, b = (int(seed[i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, _l, s = colorsys.rgb_to_hls(r, g, b)
    s = min(0.85, max(0.45, s))

    def c(l, sat=s):
        return "#%02X%02X%02X" % tuple(int(round(255 * x)) for x in colorsys.hls_to_rgb(h, l, sat))
    return {"seed": seed,
            "light": {"accent": c(0.42), "accentText": c(0.34), "accent2": c(0.76, s * 0.8), "sel": c(0.95, 0.6), "link": c(0.38)},
            "dark": {"accent": c(0.64), "accentText": c(0.75), "accent2": c(0.30), "sel": c(0.17, 0.45), "link": c(0.72)}}


def count_wifi(parts):
    n = 0
    for p in parts:
        f = Path(p) / "wifi" / "WifiConfigStore.xml"
        if f.is_file():
            n += f.read_text(errors="replace").count("<Network>")
    return n


def plan_summary(parts):
    apps = dirs = linux = 0
    names = []
    for p in parts:
        f = Path(p) / "plan.txt"
        if not f.is_file():
            continue
        for line in f.read_text(errors="replace").splitlines():
            k = line.split("|", 1)[0]
            if k == "APP":
                apps += 1
            elif k == "LINUX":
                linux += 1
            elif k in ("DIR", "TOP"):
                dirs += 1
                names.append(line.split("|")[1])
    return {"apps": apps, "linux": linux, "folders": dirs, "folderNames": names[:12]}


class Backend(QObject):
    output = Signal(str, str)
    finished = Signal(str, int)

    def __init__(self, mode):
        super().__init__()
        self._mode = mode
        self._procs = {}

    # ---------------------------------------------------------------- facts
    @Property(str, constant=True)
    def mode(self):
        return self._mode

    @Property(bool, constant=True)
    def mock(self):
        return MOCK

    @Property(str, constant=True)
    def version(self):
        return VERSION

    @Property(str, constant=True)
    def helper(self):
        return HELPER

    @Property(bool, constant=True)
    def firstRun(self):
        return "--first-run" in sys.argv or os.environ.get("S6_FIRST_RUN") == "1"

    @Property(str, constant=True)
    def userName(self):
        return os.environ.get("USER", "")

    @Property(str, constant=True)
    def home(self):
        return str(Path.home())

    @Slot(result=str)
    def tabletInfo(self):
        """Battery, storage, memory, temperature, versions and S Pen detection, straight from the system."""
        def rd(path, default=""):
            try:
                return Path(path).read_text().strip()
            except Exception:
                return default
        info = {}
        for ps in sorted(Path("/sys/class/power_supply").glob("*")):
            if rd(ps / "type") == "Battery":
                cap = rd(ps / "capacity")
                full, design = rd(ps / "charge_full") or rd(ps / "energy_full"), rd(ps / "charge_full_design") or rd(ps / "energy_full_design")
                temp = rd(ps / "temp")
                info["battery"] = {"level": int(cap) if cap.isdigit() else -1, "status": rd(ps / "status", "Unknown"),
                                   "health": round(100 * int(full) / int(design)) if full.isdigit() and design.isdigit() and int(design) > 0 else -1,
                                   "temp": round(int(temp) / 10, 1) if temp.lstrip("-").isdigit() else None,
                                   "cycles": rd(ps / "cycle_count")}
                break
        try:
            st = os.statvfs(str(Path.home()))
            info["storage"] = {"free": st.f_bavail * st.f_frsize, "total": st.f_blocks * st.f_frsize}
        except Exception:
            pass
        mem = {}
        for line in rd("/proc/meminfo").splitlines():
            k, _, v = line.partition(":")
            if k in ("MemTotal", "MemAvailable", "SwapTotal", "SwapFree"):
                mem[k] = int(v.split()[0]) * 1024
        info["memory"] = mem
        temps = []
        for z in Path("/sys/class/thermal").glob("thermal_zone*"):
            t = rd(z / "temp")
            if t.lstrip("-").isdigit() and 0 < int(t) < 150000:
                temps.append(int(t) / 1000)
        info["cpuTemp"] = round(max(temps), 1) if temps else None
        info["system"] = rd("/etc/t860-release", "Fedora")
        info["kernel"] = os.uname().release
        info["uptime"] = int(float((rd("/proc/uptime", "0").split() or ["0"])[0]))
        devs = rd("/proc/bus/input/devices").lower()
        info["pen"] = any(w in devs for w in ("s pen", "spen", "stylus", "wacom", " pen"))
        if MOCK:
            info = {"battery": {"level": 76, "status": "Charging", "health": 91, "temp": 31.4, "cycles": ""},
                    "storage": {"free": 71 * 2**30, "total": 105 * 2**30},
                    "memory": {"MemTotal": 5.6 * 2**30, "MemAvailable": 3.1 * 2**30, "SwapTotal": 5.6 * 2**30, "SwapFree": 5.4 * 2**30},
                    "cpuTemp": 42.0, "system": "Fedora 44 KDE / SM-T860 / GPU18 / 2026-10-29", "kernel": "6.18.59-t860-gpu18",
                    "uptime": 7380, "pen": False}
        return json.dumps(info)

    @Slot(result=str)
    def setupState(self):
        f = STATE / "setup.json"
        try:
            d = json.loads(f.read_text())
        except Exception:
            d = {}
        if MOCK and not d:
            d = {"user": "alex", "fullName": "Alex Doe", "gapps": "1", "theme": "dark"}
        return json.dumps(d)

    @Slot(str, result=str)
    def env(self, name):
        return os.environ.get(name, "")

    @Slot(str, result=bool)
    def which(self, cmd):
        if MOCK:
            return True
        return any((Path(p) / cmd).exists() for p in os.environ.get("PATH", "").split(":"))

    @Slot(str, result=str)
    def read(self, path):
        try:
            return Path(path).read_text(errors="replace")
        except Exception:
            return ""

    @Slot(str, result=bool)
    def exists(self, path):
        return Path(path).exists()

    @Slot(result=str)
    def packageInfo(self):
        info = package_parts()
        info["settings"] = read_settings(info["parts"])
        info["wifi"] = count_wifi(info["parts"])
        info.update(plan_summary(info["parts"]))
        seed = _hex_seed(info["settings"].get("theme", ""))
        if not seed:
            for p in info["parts"]:
                if (Path(p) / "settings" / "wallpaper").is_file():
                    seed = _wallpaper_seed(Path(p) / "settings" / "wallpaper")
                    break
        info["tint"] = accent_palette(seed)
        if MOCK and not info["parts"]:
            info = {"id": "20261114-121139", "parts": ["/var/lib/s6migrate/package-20261114-121139-part1", "/run/s6migrate/sde1/S6Migrate/20261114-121139"],
                    "want": 2, "wifi": 4, "apps": 9, "linux": 2, "folders": 7,
                    "folderNames": ["DCIM", "Download", "Documents", "Pictures", "ArtStuff", "Music", "Telegram"],
                    "settings": {"device_name": "Alex's Tab S6", "timezone": "America/Chicago", "locale": "en-US",
                                 "night_mode": "2", "wallpaper": True}}
            w = os.environ.get("S6_MOCK_ANDROID_WALL")
            info["tint"] = accent_palette(_wallpaper_seed(w) if w else "#B3261E")
        return json.dumps(info)

    @Slot(result=str)
    def wallpapers(self):
        """Backdrops for S6 Setup: Fedora's default wallpaper, and the Android one from the package (shown blurred)."""
        from PySide6.QtGui import QImageReader
        ok = {bytes(f).decode() for f in QImageReader.supportedImageFormats()}

        def readable(f):
            try:
                return f.is_file() and os.access(f, os.R_OK) and (not f.suffix or f.suffix[1:].lower() in ok)
            except OSError:
                return False

        def biggest(files):
            files = [f for f in files if readable(f)]
            # prefer formats every Qt build reads, then the largest picture
            files.sort(key=lambda f: (f.suffix.lower() in (".png", ".jpg", ".jpeg"), f.stat().st_size), reverse=True)
            return files[0] if files else None

        out = {"default": "", "android": ""}
        if MOCK and os.environ.get("S6_MOCK_WALL"):
            out["default"] = QUrl.fromLocalFile(os.environ["S6_MOCK_WALL"]).toString()
        else:
            cands = []
            for pat in ("wallpapers/F[0-9]*/contents/images*/*", "wallpapers/Fedora*/contents/images*/*",
                        "backgrounds/f[0-9]*/default/*", "backgrounds/default.*", "wallpapers/Next/contents/images*/*"):
                cands += sorted(Path("/usr/share").glob(pat), reverse=True)
                if biggest(cands):
                    break
            f = biggest(cands)
            if f:
                out["default"] = QUrl.fromLocalFile(str(f)).toString()
        if MOCK and os.environ.get("S6_MOCK_ANDROID_WALL"):
            out["android"] = QUrl.fromLocalFile(os.environ["S6_MOCK_ANDROID_WALL"]).toString()
        else:
            for p in package_parts()["parts"]:
                f = Path(p) / "settings" / "wallpaper"
                if readable(f):
                    out["android"] = QUrl.fromLocalFile(str(f)).toString()
                    break
        return json.dumps(out)

    @Slot(str, result=str)
    def json(self, path):
        try:
            return json.dumps(json.loads(Path(path).read_text()))
        except Exception:
            return "{}"

    @Slot(str, str, result=bool)
    def writeJson(self, path, text):
        try:
            Path(path).parent.mkdir(parents=True, exist_ok=True)
            Path(path).write_text(text)
            return True
        except Exception:
            return False

    @Slot(result="QVariantList")
    def timeZones(self):
        """Every time zone as {id, label}: "Chicago, America (UTC-06:00)", sorted by region and city."""
        import datetime
        try:
            from zoneinfo import ZoneInfo, available_timezones
            names = available_timezones()
        except Exception:
            return [{"id": "UTC", "label": "UTC"}]
        regions = ("Africa", "America", "Antarctica", "Arctic", "Asia", "Atlantic", "Australia", "Europe", "Indian", "Pacific")
        out = []
        now = datetime.datetime.now(datetime.timezone.utc)
        for n in names:
            if n.split("/")[0] not in regions or n.count("/") > 2:
                continue
            try:
                off = now.astimezone(ZoneInfo(n)).utcoffset()
            except Exception:
                continue
            mins = int(off.total_seconds() // 60)
            sign = "+" if mins >= 0 else "-"
            parts = n.split("/")
            place = ", ".join(x.replace("_", " ") for x in reversed(parts[1:])) + ", " + parts[0]
            out.append({"id": n, "label": "%s (UTC%s%02d:%02d)" % (place, sign, abs(mins) // 60, abs(mins) % 60),
                        "key": (parts[0], place)})
        out.sort(key=lambda o: o["key"])
        for o in out:
            del o["key"]
        return [{"id": "UTC", "label": "UTC (no time zone)"}] + out

    @Slot(result="QStringList")
    def languages(self):
        """Language codes Fedora can use, like "en-US" (from localectl; glibc-all-langpacks is installed)."""
        codes = []
        try:
            r = subprocess.run(["localectl", "list-locales"], capture_output=True, text=True, timeout=10)
            for line in r.stdout.split():
                if line.endswith(".UTF-8") and "@" not in line:
                    c = line[:-6].replace("_", "-")
                    if c not in codes:
                        codes.append(c)
        except Exception:
            pass
        return codes or ["en-US", "en-GB", "es-ES", "es-MX", "fr-FR", "de-DE", "it-IT", "pt-BR", "pt-PT", "nl-NL",
                         "pl-PL", "ru-RU", "uk-UA", "tr-TR", "ar-SA", "hi-IN", "ja-JP", "ko-KR", "zh-CN", "zh-TW"]

    @Slot(str, result=str)
    def suggestUser(self, full):
        u = re.sub(r"[^a-z0-9]", "", (full.split() or [""])[0].lower())
        if not u or not u[0].isalpha():
            u = "user" + u
        return u[:24]

    # ---------------------------------------------------------------- commands
    @Slot(str, "QVariantList")
    def run(self, task, argv):
        argv = [str(a) for a in argv]
        if MOCK:
            self._mock(task, argv)
            return
        p = QProcess(self)
        p.setProcessChannelMode(QProcess.MergedChannels)
        buf = {"b": b""}

        def ready():
            buf["b"] += bytes(p.readAll())
            *lines, buf["b"] = re.split(rb"[\r\n]", buf["b"])
            for ln in lines:
                t = ln.decode(errors="replace").strip()
                if t:
                    self.output.emit(task, t)

        def done(code, _status):
            ready()
            if buf["b"].strip():
                self.output.emit(task, buf["b"].decode(errors="replace").strip())
            self._procs.pop(task, None)
            self.finished.emit(task, code)

        p.readyReadStandardOutput.connect(ready)
        p.finished.connect(done)
        p.errorOccurred.connect(lambda e: (self.output.emit(task, f"could not start {argv[0]}"),
                                           self.finished.emit(task, 127)) if e == QProcess.FailedToStart else None)
        self._procs[task] = p
        p.start(argv[0], argv[1:])

    @Slot(str, "QVariantList", str)
    def runInput(self, task, argv, text):
        """Like run, with text on the command's input (a password never goes on the command line)."""
        self.run(task, argv)
        p = self._procs.get(task)
        if p:
            p.write(text.encode())
            p.closeWriteChannel()

    @Slot(str)
    def detach(self, cmd):
        if not MOCK:
            QProcess.startDetached("/bin/sh", ["-c", cmd])

    def _mock(self, task, argv):
        lines = [f"(simulated) {' '.join(shlex.quote(a) for a in argv[:4])}"]
        if "create-user" in argv:
            lines = ["useradd: created " + argv[argv.index("create-user") + 1], "groups: wheel, video, input", "home folder ready"]
        elif "settings" in argv:
            lines = ["time zone set: " + argv[argv.index("settings") + 1], "language set: " + argv[argv.index("settings") + 2], "device name set"]
        elif "tune" in argv:
            lines = ["tune-up " + argv[argv.index("tune") + 1] + ": on"]
        elif "prepare-look" in argv:
            lines = ["look and feel: org.s6migrate." + argv[argv.index("prepare-look") + 2], "colours, borders, file manager: set", "prepared"]
        if "find-parts" in argv:
            lines = ["PART|/var/lib/s6migrate/package-20261114-121139-part1|copied", "PART|/run/s6migrate/sde1/S6Migrate/20261114-121139|usb"]
        elif "wifi-list" in argv:
            lines = ["NET|Home WiFi|78|WPA2|yes", "NET|Neighbor 5G|54|WPA2|no", "NET|CoffeeShop|31||no",
                     "NET|Library Guest|44||no", "NET|DIRECT-printer|22|WPA2|no", "NET|Upstairs|61|WPA2|no"]
        elif any("s6-android" in x for x in argv) and "status" in argv:
            lines = ["Android: running, using about 820 MB", "Open Android app windows: 1"]
        elif "get-updates" in argv:
            lines = ["Security\tfirefox-159.0-1.fc44.aarch64", "Bug fix\tkwin-6.7.6-1.fc44.aarch64", "Enhancement\tmesa-26.2.1-1.fc44.aarch64"]
        elif "restore-files" in argv:
            lines = [f"  checking {i} of 120" for i in range(0, 121, 30)] + ["== 3/7 Restore your folders ==", "  DCIM -> ~/Pictures/DCIM", "  Download -> ~/Downloads"]
        steps = iter(lines)

        def tick():
            try:
                self.output.emit(task, next(steps))
                QTimer.singleShot(120, tick)
            except StopIteration:
                self.finished.emit(task, 0)

        QTimer.singleShot(150, tick)


def build(mode, qml_name):
    if mode == "setup":
        os.environ.setdefault("QT_IM_MODULE", "qtvirtualkeyboard")   # our own touch keyboard, before any desktop
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    app = QGuiApplication.instance() or QGuiApplication(sys.argv)
    app.setApplicationName("S6 Migrate" if mode == "setup" else "S6 Companion")
    app.setDesktopFileName("s6-companion" if mode == "companion" else "s6-setup")
    for ic in ("/usr/local/share/icons/hicolor/scalable/apps/s6-companion.svg", str(HERE.parent / "icons" / "s6-companion.svg")):
        if os.path.exists(ic):
            app.setWindowIcon(QIcon(ic)); break
    fams = load_fonts()
    app.setFont(QFont("Red Hat Text" if "Red Hat Text" in fams else "Noto Sans", 11))
    engine = QQmlApplicationEngine()
    backend = Backend(mode)
    engine._backend = backend   # keep it alive
    engine.rootContext().setContextProperty("backend", backend)
    engine.rootContext().setContextProperty("hasRedHat", "Red Hat Display" in fams)
    engine.addImportPath(str(HERE / "qml"))
    engine.load(QUrl.fromLocalFile(str(HERE / "qml" / qml_name)))
    if not engine.rootObjects():
        sys.exit(1)
    return app, engine


def main(mode, qml_name):
    app, engine = build(mode, qml_name)
    sys.exit(app.exec())
