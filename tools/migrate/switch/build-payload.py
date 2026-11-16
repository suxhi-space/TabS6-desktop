#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Build the TWRP switch script with S6 Migrate's Fedora files embedded (same result as the Android app).

usage: build-payload.py rehearsal|switch OUTFILE
Reads tools/migrate/fedora/install.list; assets resolve like the app's assets (tools/migrate/lib,
tools/migrate, android/app/src/main/fontassets). .ttf files are embedded as base64 text.
"""
import base64, sys, time
from pathlib import Path

root = Path(__file__).resolve().parents[3]
asset_dirs = [root / "tools/migrate/lib", root / "tools/migrate", root / "android/app/src/main/fontassets"]


def asset(name):
    for d in asset_dirs:
        if (d / name).is_file():
            return (d / name).read_bytes()
    raise SystemExit(f"missing asset: {name}")


def build(mode, tz="America/Chicago", lang="en-US", name="Test Tab S6"):
    script = asset("switch/update-binary").decode()
    if "# @S6_EMBED@" not in script:
        raise SystemExit("no embed marker")
    tag = "S6_EOF_%x" % time.time_ns()
    import re, datetime
    assert re.fullmatch(r"[A-Za-z0-9_/+-]{1,64}", tz) and re.fullmatch(r"[a-z]{2,3}(-[A-Z]{2})?", lang) and re.fullmatch(r"[\w .'-]{1,40}", name)
    now = datetime.datetime.now(datetime.timezone.utc)
    out = [f"S6_EMBEDDED=1\nS6_MODE={mode}\nS6_TZ='{tz}'\nS6_LANG='{lang}'\nS6_NAME='{name}'\n"
           f"S6_TIME='{now:%Y%m%d%H%M.%S}'\nS6_EPOCH={int(now.timestamp())}\nmkdir -p \"$W/zip/s6migrate\"\n"]
    lst = []
    for i, line in enumerate(asset("fedora/install.list").decode().splitlines()):
        if not line.strip() or line.startswith("#"):
            continue
        a, dest, mode_, owner = (line.split("|") + ["", "", ""])[:4]
        data = asset(a)
        text = base64.encodebytes(data).decode() if a.endswith((".ttf", ".png")) else data.decode().replace("\r\n", "\n")
        if tag in text:
            raise SystemExit("tag clash")
        if not text.endswith("\n"):
            text += "\n"
        name = f"f{i}"
        out.append(f"cat > \"$W/zip/s6migrate/{name}\" <<'{tag}'\n{text}{tag}\n")
        lst.append(f"{name}|{dest}|{mode_}|{owner}")
    out.append(f"cat > \"$W/zip/s6migrate/install.list\" <<'{tag}'\n" + "\n".join(lst) + f"\n{tag}\n")
    if mode == "rehearsal":
        out.append("echo 'checks only, nothing is erased' > \"$W/zip/s6migrate/REHEARSAL\"\n")
    return script.replace("# @S6_EMBED@", "".join(out))


if __name__ == "__main__":
    # build-payload.py rehearsal|switch OUTFILE [TIMEZONE LANGUAGE "DEVICE NAME"]   (the app passes the user's choices)
    Path(sys.argv[2]).write_text(build(sys.argv[1], *sys.argv[3:6]))
