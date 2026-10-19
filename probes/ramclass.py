"""Merge p7800-ramclass.lua runs: console RAM as ranges by class, with the
symbol file's names. Usage: ramclass.py SYMFILE run_dir..."""
import sys

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
        if 0x1800 <= a <= 0x27FF:
            sym.setdefault(a, p[1])
merged = {}
for d in sys.argv[2:]:
    for a, ks in load(d + "/ramclass.log").items():
        merged.setdefault(a, set()).update(ks)

def kind(a):
    if 0x2040 <= a <= 0x20FF:
        return "zero page"
    if 0x2140 <= a <= 0x21FF:
        return "stack"
    ks = merged.get(a, set())
    if "X" in ks:
        return "code"
    if ks & {"L", "D"}:
        return "MARIA lists"
    if "G" in ks:
        return "MARIA graphics"
    if "W" in ks:
        return "CPU data"
    return "unused"

runs = []
a = 0x1800
while a <= 0x27FF:
    k = kind(a)
    b = a
    while b + 1 <= 0x27FF and kind(b + 1) == k:
        b += 1
    runs.append((a, b, k))
    a = b + 1
tot = {}
for a, b, k in runs:
    tot[k] = tot.get(k, 0) + b - a + 1
for a, b, k in runs:
    if b - a + 1 >= 4 or k != "unused":
        names = [sym[x] for x in range(a, b + 1) if x in sym][:4]
        print("$%04X-$%04X %5d  %-14s %s" % (a, b, b - a + 1, k, " ".join(names)))
print()
for k, n in sorted(tot.items(), key=lambda kv: -kv[1]):
    print("%-14s %5d" % (k, n))
