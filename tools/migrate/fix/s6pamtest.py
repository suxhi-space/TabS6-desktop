#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-only
# Runs Fedora's own login checks (PAM) the way SDDM does, inside Fedora (chroot from TWRP), and when one fails,
# tests each rule on its own to name the one that refuses. Prints lines for S6Migrate-FIX.zip:
#   RESULT <service> <user> <stage> <ok|code> <text>
#   PROBE  <service> <stage> <module> <ok|code> <text>
#   LOG    <message from a module>
import ctypes, ctypes.util, os, socket, sys

pam = ctypes.CDLL(ctypes.util.find_library("pam") or "libpam.so.0")
libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6")
libc.strdup.restype = ctypes.c_void_p; libc.strdup.argtypes = [ctypes.c_char_p]
libc.calloc.restype = ctypes.c_void_p; libc.calloc.argtypes = [ctypes.c_size_t, ctypes.c_size_t]

class Msg(ctypes.Structure): _fields_ = [("style", ctypes.c_int), ("msg", ctypes.c_char_p)]
class Resp(ctypes.Structure): _fields_ = [("resp", ctypes.c_void_p), ("code", ctypes.c_int)]
CONV = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.POINTER(Msg)),
                        ctypes.POINTER(ctypes.POINTER(Resp)), ctypes.c_void_p)
class Conv(ctypes.Structure): _fields_ = [("conv", CONV), ("data", ctypes.c_void_p)]
pam.pam_strerror.restype = ctypes.c_char_p
pam.pam_start.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.POINTER(Conv), ctypes.POINTER(ctypes.c_void_p)]
for f in ("pam_authenticate", "pam_acct_mgmt"): getattr(pam, f).argtypes = [ctypes.c_void_p, ctypes.c_int]
pam.pam_end.argtypes = [ctypes.c_void_p, ctypes.c_int]
pam.pam_strerror.argtypes = [ctypes.c_void_p, ctypes.c_int]

PASSWORD = b""
def _conv(n, msgs, resp, data):
    arr = libc.calloc(n, ctypes.sizeof(Resp))
    r = ctypes.cast(arr, ctypes.POINTER(Resp))
    for i in range(n):
        if msgs[i].contents.style in (1, 2):   # PAM_PROMPT_ECHO_OFF / ON
            r[i].resp = libc.strdup(PASSWORD)
    resp[0] = r
    return 0
conv_cb = CONV(_conv)

# Collect what modules log (they write to /dev/log).
log = None
try:
    if not os.path.exists("/dev/log"):
        log = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM); log.bind("/dev/log"); log.settimeout(0.05)
except OSError:
    log = None
def drain():
    if not log: return
    while True:
        try: m = log.recv(4096)
        except OSError: break
        t = m.decode("utf-8", "replace"); t = t.split(": ", 1)[-1] if t.startswith("<") else t
        print("LOG", t.strip()[:200])

def run(service, user, stages):
    h = ctypes.c_void_p(); c = Conv(conv_cb, None)
    rc = pam.pam_start(service.encode(), user.encode(), ctypes.byref(c), ctypes.byref(h))
    if rc != 0: return [("start", rc, "pam_start failed")]
    out = []
    for st in stages:
        rc = pam.pam_authenticate(h, 0) if st == "auth" else pam.pam_acct_mgmt(h, 0)
        out.append((st, rc, (pam.pam_strerror(h, rc) or b"").decode()))
        if rc != 0: break
    pam.pam_end(h, 0); drain()
    return out

def expand(service, typ, seen=None):
    """The module lines of one type, following include/substack."""
    seen = seen or set()
    if service in seen: return []
    seen.add(service); lines = []
    try: txt = open("/etc/pam.d/" + service).read().splitlines()
    except OSError: return [("MISSING-FILE", service)]
    for raw in txt:
        l = raw.strip()
        if not l or l.startswith("#"): continue
        t = l.lstrip("-")
        if not t.startswith(typ): continue
        rest = t[len(typ):].strip()
        if rest.startswith("include") or rest.startswith("substack"):
            lines += expand(rest.split()[1], typ, seen); continue
        if rest.startswith("["): ctrl, _, rest = rest[1:].partition("]")
        else: ctrl, _, rest = rest.partition(" ")
        rest = rest.strip()
        if rest: lines.append((rest.split()[0], rest))
    return lines

def probe(service, user, stage):
    typ = "auth" if stage == "auth" else "account"
    for mod, args in expand(service, typ):
        if mod == "MISSING-FILE": print("PROBE", service, stage, args, "missing", "included file is missing"); continue
        open("/etc/pam.d/s6fix-probe", "w").write("%s required %s\n" % (typ, args))
        res = run("s6fix-probe", user, [stage])[-1]
        print("PROBE", service, stage, mod, "ok" if res[1] == 0 else res[1], res[2])
    try: os.remove("/etc/pam.d/s6fix-probe")
    except OSError: pass

tests = [("sddm-autologin", "s6setup", b""), ("sddm", "s6setup", b"123456"), ("sddm", "fedora", b"123456")]
for service, user, pw in tests:
    if not os.path.exists("/etc/pam.d/" + service): print("RESULT", service, user, "-", "missing", "no such login rules"); continue
    PASSWORD = pw
    res = run(service, user, ["auth", "account"])
    for st, rc, txt in res:
        print("RESULT", service, user, st, "ok" if rc == 0 else rc, txt)
    if res and res[-1][1] != 0:
        probe(service, user, res[-1][0])
if log:
    log.close(); os.remove("/dev/log")
