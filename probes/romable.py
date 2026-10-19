"""Could it be ROM? Merges probes/tmp-romable.lua's runs (romable.log) with
p7800-ramclass.lua's (ramclass.log: MARIA's list and graphics reads) into
console RAM's and cart RAM's bytes by class:
  list      a display list or DLL byte (RAM by the rules)
  graphics  read by MARIA, never changed in play (a load's: pseudo-ROM)
  graphics* read by MARIA and changed in play
  dead      written, never read by the CPU or MARIA
  rom       the CPU's data, never changed in play, one value in every scene
  rom/scn   the same, one value a scene but not the same in all (scene pages)
  rom0      read, never written after the boot's clear (always 0)
  ram       the CPU's data changed in play
Usage: romable.py SYMFILE --rb run_dir... --rc run_dir... [--ranges]"""
import argparse
import os
from collections import defaultdict

ap = argparse.ArgumentParser()
ap.add_argument("sym")
ap.add_argument("--rb", nargs="+", required=True)
ap.add_argument("--rc", nargs="+", default=[])
ap.add_argument("--ranges", action="store_true")
o = ap.parse_args()

sym = {}
for ln in open(o.sym):
    p = ln.split()
    if len(p) == 2:
        try:
            a = int(p[0], 16)
        except ValueError:
            continue
        if 0x1800 <= a <= 0x27FF or 0x4000 <= a <= 0x7FFF:
            sym.setdefault(a, p[1])

maria = defaultdict(set)
for d in o.rc:
    for ln in open(os.path.join(d, "ramclass.log")):
        k, page, bits = ln.split()
        if k not in "LDG":
            continue
        page = int(page, 16)
        for i, ch in enumerate(bits):
            v = int(ch, 16)
            for j in range(4):
                if v & (8 >> j):
                    maria[page * 256 + 4 * i + j].add(k)

# addr -> {scene: [loadw, playw, playchg, reads, set(values)]}
rec = defaultdict(lambda: defaultdict(lambda: [0, 0, 0, 0, set()]))
for d in o.rb:
    for ln in open(os.path.join(d, "romable.log")):
        p = ln.split()
        a, sc = int(p[0], 16), int(p[1], 16)
        r = rec[a][sc]
        for i in range(4):
            r[i] += int(p[2 + i])
        if len(p) > 6:
            r[4] |= {int(v, 16) for v in p[6].split(",")}


def final(vals):
    """the value a byte keeps: its one value, or with a clear before it the
    other one (None: more than that)"""
    v = set(vals)
    if len(v) == 2 and 0 in v:
        v.discard(0)
    return next(iter(v)) if len(v) == 1 else None


def kind(a):
    m = maria.get(a, set())
    if "L" in m or "D" in m:
        return "list"
    t = rec.get(a)
    if not t:
        return "graphics" if m else None
    writes = sum(r[0] + r[1] for r in t.values())
    chg = sum(r[2] for r in t.values())
    reads = sum(r[3] for r in t.values())
    if "G" in m:
        return "graphics*" if chg else "graphics"
    if not writes:
        return "rom0" if reads else None
    if not reads:
        return "dead"
    if chg:
        return "ram"
    vs = [final(r[4]) for r in t.values() if r[0] + r[1]]
    if any(v is None for v in vs):
        return "ram"
    return "rom" if len(set(vs)) == 1 else "rom/scn"


ORDER = ["list", "graphics", "graphics*", "dead", "rom", "rom/scn", "rom0", "ram"]
for lo, hi, name in ((0x1800, 0x27FF, "console RAM"), (0x4000, 0x7FFF, "cart RAM")):
    tot = defaultdict(int)
    out = []
    a = lo
    while a <= hi:
        k = kind(a)
        b = a
        while b + 1 <= hi and kind(b + 1) == k:
            b += 1
        if k:
            tot[k] += b - a + 1
            names = [sym[x] for x in range(a, b + 1) if x in sym][:4]
            out.append("$%04X-$%04X %5d  %-10s %s" % (a, b, b - a + 1, k, " ".join(names)))
        a = b + 1
    print("== %s: %s" % (name, ", ".join("%s %d" % (k, tot[k]) for k in ORDER if tot[k])))
    if o.ranges:
        print("\n".join(out))
