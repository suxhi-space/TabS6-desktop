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
    # S6 Migrate's Fedora files, embedded like the switch embeds them (see switch/build-payload.py).
    import base64, re, time
    mig = here.parent
    dirs = [mig / "lib", mig, mig.parent.parent / "android/app/src/main/fontassets"]
    def asset(n):
        for d in dirs:
            if (d / n).is_file():
                return (d / n).read_bytes()
        raise SystemExit("missing asset: " + n)
    tag = "S6F_EOF_%x" % time.time_ns()
    ver = re.search(r'^VERSION = "(.*)"', (mig / "fedora/app/s6ui.py").read_text(), re.M).group(1)
    parts = ["S6_FIX_VERSION=%s\n" % ver]
    for line in (mig / "fedora/install.list").read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        a, dest, mode_, owner = (line.split("|") + ["", "", ""])[:4]
        if dest.startswith(("/var/lib/s6migrate/setup-home/", "/etc/sddm.conf.d/")) or owner == "s6setup":
            continue
        data = asset(a)
        text = base64.encodebytes(data).decode() if a.endswith((".ttf", ".png")) else data.decode().replace("\r\n", "\n")
        assert tag not in text
        if not text.endswith("\n"):
            text += "\n"
        keep = dest == "/etc/NetworkManager/conf.d/60-s6migrate-wifi.conf"   # a setting the user may have changed
        target = '"$ROOT%s"' % dest if not keep else '"$ROOT%s.new"' % dest
        parts.append('mkdir -p "$(dirname "$ROOT%s")"; cat > %s <<\'%s\'\n%s%s\nchmod %s %s; n_s6=$((n_s6+1))\n'
                     % (dest, target, tag, text, tag, mode_ or "644", target))
        if keep:
            parts.append('[ -e "$ROOT%s" ] && rm -f "$ROOT%s.new" || mv "$ROOT%s.new" "$ROOT%s"\n' % (dest, dest, dest, dest))
    ub = ub.replace("# @S6FILES@\n", "".join(parts))
    z.writestr(i, ub)
    z.writestr("META-INF/com/google/android/updater-script", "# S6 Migrate fix: the work is done by update-binary\n")
print(out)
