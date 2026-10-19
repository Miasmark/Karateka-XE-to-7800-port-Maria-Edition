"""The ROM by use (FINDINGS "The ROM by scene: the plan"): probes/tmp-romuse.lua's
runs merged with the build's map (work/karateka7800.map). CPU side: each map
item's bytes executed or read in play (or text), only at loads, or never, and
in how many scenes; MARIA side: each address fetched by how many scenes
(shared, one scene's, none), by region.
    python probes/romuse.py MAPFILE RUN_DIR... [--items]"""
import re
import sys
from collections import defaultdict

args = [a for a in sys.argv[1:] if not a.startswith("--")]
mapf, runs = args[0], args[1:]
use = defaultdict(lambda: defaultdict(set))    # (bank, kind) -> addr -> {(phase, scene)}
for d in runs:
    for ln in open(d + "/romuse.log"):
        bk, ph, sc, kind, page, bits = ln.split()
        page = int(page, 16)
        for i, ch in enumerate(bits):
            v = int(ch, 16)
            for j in range(4):
                if v & (8 >> j):
                    use[(bk, kind)][page * 256 + 4 * i + j].add((ph, int(sc)))

# the map: "; name ($base): n bytes used" then "$lo-$hi n what"
items = []
cur = None
for ln in open(mapf):
    if ln.startswith(";"):
        name = ln[2:].split(" (")[0]
        cur = "F" if name == "fixed" else name.split()[-1]
        continue
    m = re.match(r"\$(\w+)-\$(\w+)\s+(-?\d+)\s+(.*)", ln.rstrip())
    if m and int(m.group(3)) > 0:
        items.append((cur, int(m.group(1), 16), int(m.group(2), 16), m.group(4)))


def kindof(w):
    return re.split(r" \(| \$|: |, ", w)[0][:34]


agg = defaultdict(lambda: defaultdict(int))     # (bank, kind) -> class -> bytes
for bk, lo, hi, w in items:
    k = kindof(w)
    for a in range(lo, hi + 1):
        ctx = use[(bk, "x")].get(a, set()) | use[(bk, "r")].get(a, set())
        if any(p in ("P", "T") for p, _ in ctx):
            scs = {s for p, s in ctx if p in ("P", "T")}
            cls = "play, %s" % ("all" if len(scs) > 1 else "one scene")
        elif ctx:
            cls = "loads only"
        else:
            cls = "never"
        agg[(bk, k)][cls] += 1
CL = ("play, all", "play, one scene", "loads only", "never")
print("CPU: bytes by use (play: executed or read in play or text; 'all': more than one scene)")
print("%-5s %-34s %s" % ("bank", "what", " ".join("%15s" % c for c in CL)))
for (bk, k), d in sorted(agg.items(), key=lambda x: (x[0][0], -sum(x[1].values()))):
    if sum(d.values()) >= 64 or "--items" in sys.argv:
        print("%-5s %-34s %s" % (bk, k, " ".join("%15d" % d.get(c, 0) for c in CL)))
tot = defaultdict(lambda: defaultdict(int))
for (bk, k), d in agg.items():
    for c, n in d.items():
        tot[bk][c] += n
print("\nCPU totals by bank:")
for bk in sorted(tot):
    print("%-5s %s" % (bk, " ".join("%s %d;" % (c, tot[bk].get(c, 0)) for c in CL)))

print("\nMARIA: addresses fetched, by region and how many scenes")
for region in sorted({bk for bk, kind in use if kind == "m"}):
    m = use[(region, "m")]
    by = defaultdict(int)
    for a, ctx in m.items():
        scs = {s for _, s in ctx}
        by["shared" if len(scs) > 1 else "scene %d" % min(scs)] += 1
    print("  %-3s %s" % (region, ", ".join("%s %d" % kv for kv in sorted(by.items()))))
