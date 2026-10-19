"""The inventory (FINDINGS "The inventory"): p7800-inventory.lua runs merged.
For every ROM byte read: which labels (stretches of the game) use it, and as
code (opcode or operand) or data. Prints, per bank and region, the bytes used
by each label alone, by several, and in all; and for scene 1's page, the
split between its stretches.

    python probes/inventory.py work/analysis/inv-*
"""
import sys
from collections import defaultdict

REGIONS = {      # the scene pages' regions (banks 0-4); the others are whole
    "scode": (0x8203, 0x9300),
    "port": (0x9300, 0x96E8),
    "common": (0x96E8, 0xA000),
    "sdata": (0xA000, 0xC000),
}
BANKS = {0: "page 0", 1: "page 1", 2: "page 2", 3: "page 3", 4: "page 4", 5: "bank 5", 6: "art bank", 15: "fixed"}


def region(bank, a):
    if bank <= 4:
        for n, (lo, hi) in REGIONS.items():
            if lo <= a < hi:
                return n
        return "low"
    return "-"


# the images the game blits (p7800-blitcensus.lua runs): their bytes, by bank
import glob
IMG = set()
for d in glob.glob("work/analysis/bcs-*"):
    for ln in open(d + "/blitcensus.log"):
        p = ln.split()
        if p[0] == "fighter" or "/ft" in p[0] or not p[1].startswith("b"):
            continue
        bank, src, rows, w = int(p[1][1:]), int(p[2], 16), int(p[3]), int(p[4])
        for a in range(src, src + 2 + rows * w):
            IMG.add((bank, a))

use = defaultdict(lambda: defaultdict(set))     # (bank, addr) -> class -> labels
for d in sys.argv[1:]:
    try:
        lines = open(d + "/inventory.txt").read().splitlines()
    except OSError:
        print("(no inventory in %s)" % d)
        continue
    for ln in lines:
        lab, bank, cls, runs = ln.split(" ", 3)
        bank = int(bank)
        for r in runs.split(","):
            lo, hi = (int(x, 16) for x in r.split("-"))
            for a in range(lo, hi + 1):
                use[(bank, a)][cls].add(lab)

labels = sorted({l for v in use.values() for s in v.values() for l in s})
print("labels:", " ".join(labels))


def kind(bank, a, cl):
    if "X" in cl or "O" in cl:
        return "code"
    return "image" if (bank, a) in IMG else "data"


# per bank and region: code and data bytes, and by how many labels
tab = defaultdict(lambda: defaultdict(int))
for (bank, a), cl in use.items():
    k = kind(bank, a, cl)
    labs = set().union(*cl.values())
    tab[(bank, region(bank, a))][k] += 1
    tab[(bank, region(bank, a))][k + " one"] += len(labs) == 1
print()
print("bytes read, by bank and region (\"one\": by a single label)")
print("%-9s %-7s %6s %6s %6s %6s %6s %6s" % ("bank", "region", "code", "(one)", "tables", "(one)", "images", "(one)"))
for (bank, reg) in sorted(tab):
    t = tab[(bank, reg)]
    print("%-9s %-7s %6d %6d %6d %6d %6d %6d" % (BANKS.get(bank, bank), reg, t["code"], t["code one"], t["data"], t["data one"], t["image"], t["image one"]))

# each label's own bytes (used by no other label), by bank
print()
own = defaultdict(lambda: defaultdict(int))
for (bank, a), cl in use.items():
    labs = set().union(*cl.values())
    if len(labs) == 1:
        k = kind(bank, a, cl)
        own[next(iter(labs))][(BANKS.get(bank, bank), k)] += 1
print("bytes only one label uses:")
for lab in labels:
    items = ", ".join("%s %s %d" % (b, k, n) for (b, k), n in sorted(own[lab].items()))
    print("  %-8s %s" % (lab, items))

# scene 1's page: the stretches' split
print()
print("page 1 (scenes 1 and 6), by which of its stretches use a byte:")
combo = defaultdict(lambda: defaultdict(int))
for (bank, a), cl in use.items():
    if bank != 1:
        continue
    labs = frozenset(l for l in set().union(*cl.values()) if l.startswith("s1") or l == "s6")
    if not labs:
        continue
    k = kind(bank, a, cl)
    combo[labs][(region(1, a), k)] += 1
for labs, t in sorted(combo.items(), key=lambda kv: -sum(kv[1].values())):
    print("  %-28s %s" % ("+".join(sorted(labs)), ", ".join("%s %s %d" % (r, k, n) for (r, k), n in sorted(t.items()))))
