"""From p7800-blitcensus.lua runs (with rows): each scenery image's row
alignments on an 8- and a 16-line zone grid, and the ROM its pre-cut copies
take (a copy at alignment p covers ceil((p + rows) / Z) zones of Z lines,
each its width; twice for an image drawn both ways). Per bank.
    python probes/rowphase.py work/analysis/bcs-*
"""
import sys
from collections import defaultdict

imgs = defaultdict(lambda: {"rows": set(), "dirs": set()})
for d in sys.argv[1:]:
    for ln in open(d + "/blitcensus.log"):
        p = ln.split()
        if p[0] == "fighter" or "/ft" in p[0] or len(p) < 9:
            continue
        kind, where, src, rows, w = p[0], p[1], int(p[2], 16), int(p[3]), int(p[4])
        k = (where, src, rows, w)
        imgs[k]["rows"].update(int(r) for r in p[8].split(","))
        imgs[k]["dirs"].add("M" if kind.startswith("M") else "N")
by = defaultdict(lambda: defaultdict(int))
movers = []
for (where, src, h, w), e in imgs.items():
    dirs = len(e["dirs"])
    raw = h * w * dirs
    by[where]["images"] += 1
    by[where]["raw"] += raw
    for Z in (8, 16):
        ph = {r % Z for r in e["rows"]}
        by[where]["ph%d" % Z] += len(ph)
        by[where]["cost%d" % Z] += sum(-(-(p + h) // Z) * Z * w for p in ph) * dirs
    if len({r % 8 for r in e["rows"]}) > 3:
        movers.append((where, "%04X" % src, h, w, len(e["rows"])))
print("%-6s %6s %7s %10s %8s %10s %8s" % ("bank", "images", "raw", "phases(8)", "ROM(8)", "phases(16)", "ROM(16)"))
tot = defaultdict(int)
for where in sorted(by):
    b = by[where]
    for k, v in b.items():
        tot[k] += v
    print("%-6s %6d %7d %10d %8d %10d %8d" % (where, b["images"], b["raw"], b["ph8"], b["cost8"], b["ph16"], b["cost16"]))
print("%-6s %6d %7d %10d %8d %10d %8d" % ("all", tot["images"], tot["raw"], tot["ph8"], tot["cost8"], tot["ph16"], tot["cost16"]))
print("images at more than 3 alignments (mod 8):", len(movers))
for m in sorted(movers, key=lambda m: -m[4])[:12]:
    print("   %s %s %dx%d at %d rows" % m)
