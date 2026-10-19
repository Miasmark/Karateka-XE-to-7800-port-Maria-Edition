"""Merge p7800-ramclass.lua runs over cart RAM (LO=4000 HI=7FFF): each byte
by what BankSet's RAM rules make of it (FINDINGS "BankSet: the CPU off
cart RAM"): code (none may run there), MARIA's lists (must be in console
RAM), graphics MARIA reads that the CPU also reads (a CPU copy and MARIA's
both needed), graphics the CPU only writes (written through $C000-$FFFF),
the CPU's own data (its own cart RAM), written but read by neither in these
runs, unused. Ranges with the symbols in them.
    python probes/cartclass.py work/karateka7800.sym work/analysis/crc*"""
import sys

LO, HI = 0x4000, 0x7FFF


def load(path):
    cls = {}
    for ln in open(path):
        k, page, bits = ln.split()
        page = int(page, 16)
        for i, ch in enumerate(bits):
            v = int(ch, 16)
            for j in range(4):
                if v & (8 >> j):
                    cls.setdefault(page * 256 + 4 * i + j, set()).add(k)
    return cls


sym = {}
for ln in open(sys.argv[1]):
    p = ln.split()
    if len(p) == 2:
        try:
            a = int(p[0], 16)
        except ValueError:
            continue
        if LO <= a <= HI:
            sym.setdefault(a, []).append(p[1])
merged = {}
for d in sys.argv[2:]:
    for a, ks in load(d + "/ramclass.log").items():
        merged.setdefault(a, set()).update(ks)


def kind(a):
    ks = merged.get(a, set())
    if "X" in ks:
        return "code"
    if ks & {"L", "D"}:
        return "MARIA lists" + (" (CPU reads)" if "R" in ks else "")
    if "G" in ks:
        return "graphics, CPU reads too" if "R" in ks else "graphics, CPU writes only"
    if "R" in ks:
        return "CPU data"
    if "W" in ks:
        return "written, not read"
    return "unused"


runs = []
a = LO
while a <= HI:
    k = kind(a)
    b = a
    while b + 1 <= HI and kind(b + 1) == k:
        b += 1
    runs.append((a, b, k))
    a = b + 1
tot = {}
for a, b, k in runs:
    tot[k] = tot.get(k, 0) + b - a + 1
print("cart RAM by class (bytes):")
for k, n in sorted(tot.items(), key=lambda kv: -kv[1]):
    print("  %-28s %6d" % (k, n))
print()
for a, b, k in runs:
    if k == "unused":
        continue
    names = [n for x in range(a, b + 1) for n in sym.get(x, [])]
    print("$%04X-$%04X %5d %-28s %s" % (a, b, b - a + 1, k, " ".join(names[:6])))
