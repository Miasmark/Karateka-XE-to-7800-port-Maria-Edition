"""Console RAM ($1800-$27FF) as a map, a character a byte, 64 a line, from
probes/romable.py's classes (its --ranges output) and the symbol file's list
pieces (L1SA0-L1SF6, TPSA0-TPSF6 and their ...E ends):
  P  a list piece of some scene's group (band or top)
  L  another display list or DLL byte MARIA reads (not a piece)
  C  the CPU's data (ram, rom, rom/scn, rom0)    x  dead (written, never read)
  G  graphics    Z  zero page and stack    .  nothing seen
then each piece group's pieces, and the totals.
    python probes/consolemap.py SYMFILE ROMABLE_RANGES.txt"""
import os
import re
import sys

sym = {}
for ln in open(sys.argv[1]):
    p = ln.split()
    if len(p) == 2:
        try:
            sym[p[1]] = int(p[0], 16)
        except ValueError:
            pass
cls = {}
for ln in open(sys.argv[2]):
    m = re.match(r"\$([0-9A-F]{4})-\$([0-9A-F]{4})\s+\d+\s+(\S+)", ln)
    if m:
        for a in range(int(m.group(1), 16), int(m.group(2), 16) + 1):
            cls[a] = m.group(3)
piece = {}
for pre in ("L1S", "TPS"):
    for let in os.environ.get("ACTIVE", "ABCDEF"):     # (ACTIVE: only these sets' pieces)
        for k in range(7):
            lo, hi = sym.get("%s%s%d" % (pre, let, k)), sym.get("%s%s%dE" % (pre, let, k))
            if lo and hi and hi > lo and 0x1800 <= lo < 0x2800:
                for a in range(lo, hi):
                    piece.setdefault(a, []).append("%s%s%d" % (pre, let, k))
CH = {"list": "L", "graphics": "G", "graphics*": "G", "dead": "x", "rom": "C", "rom/scn": "C", "rom0": "C", "ram": "C"}
tot = {}
for row in range(0x1800, 0x2800, 64):
    s = ""
    for a in range(row, row + 64):
        if 0x2040 <= a < 0x2100 or 0x2140 <= a < 0x2200:
            c = "Z"
        elif a in piece:
            c = "P"
        else:
            c = CH.get(cls.get(a), ".")
        s += c
        tot[c] = tot.get(c, 0) + 1
    print("$%04X %s" % (row, s))
print(" ".join("%s %d" % kv for kv in sorted(tot.items())))
