"""The ROM by scene, step 2's ledger (FINDINGS "The ROM by scene: step 2"):
each map item of the CPU's banks (work/karateka7800.map; a byte belongs to
the smallest item over it) by its use in probes/tmp-romuse.lua's runs: in
play or text by more than one scene ("shared"), by one ("scene N"), only at
loads, or never. Summed by item kind and bank.
    python probes/romplan.py MAPFILE RUN_DIR..."""
import re
import sys
from collections import defaultdict

mapf, runs = sys.argv[1], sys.argv[2:]
# (an executed opcode's operand bytes are used too: the probe marks only the
# opcode's fetch. Each instruction's length from the cartridge beside the
# map, the CPU's half: bank b at file 128 + b x $4000, the fixed one bank 7)
CART = open(mapf[:-4] + ".a78", "rb").read()[128:]
LEN1 = {0x00, 0x08, 0x18, 0x28, 0x38, 0x40, 0x48, 0x58, 0x60, 0x68, 0x78, 0x88, 0x8A, 0x98, 0x9A, 0xA8, 0xAA,
        0xB8, 0xBA, 0xC8, 0xCA, 0xD8, 0xE8, 0xEA, 0xF8, 0x0A, 0x2A, 0x4A, 0x6A}


def oplen(op):
    if op in LEN1:
        return 1
    if op in (0x20, 0x4C, 0x6C):
        return 3
    cc, bbb = op & 3, (op >> 2) & 7
    if cc == 1:
        return 3 if bbb in (3, 6, 7) else 2
    if cc == 2:
        return 3 if bbb in (3, 7) else 2
    if cc == 0:
        return 3 if bbb in (3, 7) else 2
    return 1


def byte_at(bk, a):
    if bk == "F":
        return CART[7 * 0x4000 + a - 0xC000]
    return CART[int(bk) * 0x4000 + a - 0x8000]
use = defaultdict(lambda: defaultdict(set))     # bank -> addr -> {(phase, scene)}
for d in runs:
    for ln in open(d + "/romuse.log"):
        bk, ph, sc, kind, page, bits = ln.split()
        if kind not in ("x", "r"):
            continue
        page = int(page, 16)
        for i, ch in enumerate(bits):
            v = int(ch, 16)
            for j in range(4):
                if v & (8 >> j):
                    ad = page * 256 + 4 * i + j
                    n = oplen(byte_at(bk, ad)) if kind == "x" and bk in "F0123456" and ad >= 0x8000 else 1
                    for k in range(n):
                        use[bk][ad + k].add((ph, int(sc)))
items = defaultdict(list)                        # bank -> [(lo, hi, what)]
cur = None
for ln in open(mapf):
    if ln.startswith(";"):
        name = ln[2:].split(" (")[0]
        cur = "F" if name == "fixed" else name.split()[-1]
        continue
    m = re.match(r"\$(\w+)-\$(\w+)\s+(-?\d+)\s+(.*)", ln.rstrip())
    if m and int(m.group(3)) > 0:
        items[cur].append((int(m.group(1), 16), int(m.group(2), 16), m.group(4)))


def kindof(w):
    return re.split(r" \(| \$|: |, ", w)[0][:34]


led = defaultdict(lambda: defaultdict(int))     # (bank, kind) -> class -> bytes
for bk, its in items.items():
    owner = {}
    for lo, hi, w in sorted(its, key=lambda t: -(t[1] - t[0])):   # (the smallest last: it wins)
        for a in range(lo, hi + 1):
            owner[a] = w
    for a, w in owner.items():
        ctx = use[bk].get(a, set())
        play = {s for p, s in ctx if p in ("P", "T")}
        if len(play) > 1:
            cls = "shared"
        elif play:
            cls = "scene %d" % min(play)
        elif ctx:
            cls = "load"
        else:
            cls = "never"
        led[(bk, kindof(w))][cls] += 1
print("%-4s %-34s %7s %7s %7s %7s  (one scene's: by scene)" % ("bank", "item", "shared", "1 scene", "load", "never"))
for (bk, k), d in sorted(led.items(), key=lambda x: (x[0][0], -sum(x[1].values()))):
    one = {c: n for c, n in d.items() if c.startswith("scene")}
    if sum(d.values()) < 100:
        continue
    print("%-4s %-34s %7d %7d %7d %7d  %s" % (bk, k, d.get("shared", 0), sum(one.values()), d.get("load", 0),
                                           d.get("never", 0), " ".join("%s:%d" % (c[6:], n) for c, n in sorted(one.items()))))
