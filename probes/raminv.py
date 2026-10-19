"""The RAM inventory (FINDINGS "What in RAM is redundant"): every byte of
console RAM and of the CPU's blocks in cart RAM, classed from
probes/tmp-romable.lua's runs (the CPU: writes at a load and in play, the
play writes that changed it, its reads, its values) and
probes/tmp-ramlive.lua's (MARIA's reads), over all the runs given:
  maria    MARIA reads it (lists, graphics)
  dead     written, never read
  zero     read, never written after the boot's clear (always 0)
  const    read, never changed in play, one value in every run
  scene    read, never changed in play, one value a scene
  load     read, written at loads only, more than one value a scene
  ram      changed in play
  unused   neither read nor written
then summed by variable (the symbol at or below the byte).
    python probes/raminv.py SYMFILE --rb RUNS... --rl RUNS... [--scene N] [--all]
--scene N: only bytes scene N's bank uses (its context in the logs).
--all: every variable, not just those with a class other than ram."""
import argparse
import bisect
from collections import defaultdict

ap = argparse.ArgumentParser()
ap.add_argument("sym")
ap.add_argument("--rb", nargs="+", required=True)
ap.add_argument("--rl", nargs="*", default=[])
ap.add_argument("--scene", type=int)
ap.add_argument("--all", action="store_true")
o = ap.parse_args()

sym = []
for ln in open(o.sym):
    p = ln.split()
    if len(p) == 2:
        try:
            sym.append((int(p[0], 16), p[1]))
        except ValueError:
            pass
SKIP = ("L1S", "TPS")          # (the list pieces' bounds: not variables)
names = sorted((a, n) for a, n in sym if not n.startswith(SKIP) and (0x1800 <= a < 0x2800 or 0x4000 <= a < 0x8000))
addrs = [a for a, _ in names]


def owner(a):
    i = bisect.bisect_right(addrs, a) - 1
    return names[i] if i >= 0 else (0, "?")


BANK = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 6: 1}
info = defaultdict(lambda: {"lw": 0, "pw": 0, "pc": 0, "rd": 0, "vals": defaultdict(set), "scenes": set()})
for d in o.rb:
    for ln in open(d + "/romable.log"):
        f = ln.split()
        a, sc = int(f[0], 16), int(f[1], 16)
        x = info[a]
        x["lw"] += int(f[2])
        x["pw"] += int(f[3])
        x["pc"] += int(f[4])
        x["rd"] += int(f[5])
        if len(f) > 6:
            x["vals"][sc] |= set(f[6].split(","))
        x["scenes"].add(sc)
maria = set()
for d in o.rl:
    for ln in open(d + "/ramlive.log"):
        ctx, kind, page, bits = ln.split()
        if kind != "m":
            continue
        page = int(page, 16)
        for i, ch in enumerate(bits):
            v = int(ch, 16)
            for j in range(4):
                if v & (8 >> j):
                    maria.add(page * 256 + 4 * i + j)


def cls(a):
    if a in maria:
        return "maria"
    x = info.get(a)
    if not x or (x["rd"] == 0 and x["lw"] + x["pw"] == 0):
        return "unused"
    if x["rd"] == 0:
        return "dead"
    if x["lw"] + x["pw"] == 0:
        return "zero"
    if x["pc"] > 0:
        return "ram"
    vs = [v for v in x["vals"].values() if v]
    if all(len(v) == 1 for v in vs):
        if len(set().union(*vs)) <= 1:
            return "const"
        return "scene"
    return "load"


ZS = set(range(0x2040, 0x2100)) | set(range(0x2140, 0x2200))
space = [a for a in range(0x1800, 0x2800) if a not in ZS] + [a for a in range(0x4000, 0x8000) if a in info]
if o.scene is not None:
    b = BANK[o.scene]
    space = [a for a in space if b in info.get(a, {"scenes": set()})["scenes"] or a in maria]
by = defaultdict(lambda: defaultdict(int))
tot = defaultdict(int)
for a in space:
    c = cls(a)
    if a >= 0x4000 and c in ("unused", "maria"):
        continue
    n = owner(a)
    by[n][c] += 1
    tot[("cart " if a >= 0x4000 else "console ") + c] += 1
print("totals:", ", ".join("%s %d" % (k, v) for k, v in sorted(tot.items())))
CL = ("maria", "ram", "load", "scene", "const", "zero", "dead", "unused")
print("%-6s %-14s %s" % ("addr", "variable", " ".join("%6s" % c for c in CL)))
for (a, n), d in sorted(by.items()):
    if not o.all and all(c in ("ram", "maria") for c in d):
        continue
    print("$%04X %-14s %s" % (a, n, " ".join("%6s" % (d.get(c, "") or "") for c in CL)))
