#!/usr/bin/env python3
# s6-keys with fake buttons (FIFOs): short and long power presses pass through unchanged, Power + Volume Down in
# either order takes a screenshot and passes nothing on, Volume Down alone does nothing.
import importlib.util, os, struct, threading, time, sys
spec = importlib.util.spec_from_loader("k", loader=None)
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "system", "s6-keys")).read()
k = importlib.util.module_from_spec(spec); exec(compile(src, "s6-keys", "exec"), k.__dict__)
import tempfile
D = tempfile.mkdtemp()
for n in ("pwr", "vol"):
    p = f"{D}/{n}"
    if os.path.exists(p): os.remove(p)
    os.mkfifo(p)
w = {}
def opener():  # keep writers so the FIFOs don't hit EOF
    for n in ("pwr", "vol"): w[n] = os.open(f"{D}/{n}", os.O_RDWR)
opener()
kinds = {}
real_open = os.open
def fake_open(p, fl, *a):
    fd = real_open(p, fl, *a)
    kinds[fd] = {f"{D}/pwr": {k.KEY_POWER}, f"{D}/vol": {k.KEY_VOLUMEDOWN}}.get(p, set())
    return fd
k.glob.glob = lambda pat: [f"{D}/pwr", f"{D}/vol"] if "event" in pat else []
k.os = type("O", (), dict(os.__dict__))()
for a in ("read", "write", "close", "environ"): setattr(k.os, a, getattr(os, a))
k.os.open = fake_open; k.os.O_RDONLY = os.O_RDONLY; k.os.O_NONBLOCK = os.O_NONBLOCK
k.keys_of = lambda fd: kinds.get(fd, set()); k.name_of = lambda fd: "fake"
r_u, w_u = os.pipe(); os.set_blocking(r_u, False)
k.virtual_power = lambda: w_u
k.fcntl = type("F", (), {"ioctl": staticmethod(lambda *a: 0)})
shots = []; k.screenshot = lambda: shots.append(time.time())
threading.Thread(target=k.main, daemon=True).start(); time.sleep(0.3)
def ev(dev, code, val): os.write(w[dev], struct.pack(k.FMT, 0, 0, k.EV_KEY, code, val))
def out():
    time.sleep(0.15); res = []
    try: data = os.read(r_u, 4096)
    except BlockingIOError: return res
    for i in range(0, len(data), k.SZ):
        _, _, t, c, v = struct.unpack(k.FMT, data[i:i+k.SZ])
        if t == k.EV_KEY: res.append(v)
    return res
# 1. short press -> passed on as down+up
ev("pwr", 116, 1); time.sleep(0.1); ev("pwr", 116, 0); assert out() == [1, 0] and len(shots) == 0, "short press"
# 2. long press -> down after HOLD, up on release
ev("pwr", 116, 1); time.sleep(0.6); assert out() == [1], "long press goes through while held"; ev("pwr", 116, 0); assert out() == [0], "long press release"
# 3. combo: power then volume down -> screenshot, nothing passed on
ev("pwr", 116, 1); time.sleep(0.08); ev("vol", 114, 1); time.sleep(0.05); ev("vol", 114, 0); ev("pwr", 116, 0); assert out() == [] and len(shots) == 1, "power then volume down"
# 4. combo the other way: volume first, then power -> screenshot
time.sleep(0.4); ev("vol", 114, 1); time.sleep(0.05); ev("pwr", 116, 1); time.sleep(0.05); ev("pwr", 116, 0); ev("vol", 114, 0); assert out() == [] and len(shots) == 2, "volume down then power"
# 5. volume alone -> nothing
time.sleep(0.4); ev("vol", 114, 1); ev("vol", 114, 0); assert out() == [] and len(shots) == 2, "volume alone"
print("s6-keys: ok")
