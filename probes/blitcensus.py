"""Sum p7800-blitcensus.lua runs: the images MARIA would need, by where they
are (a scene page, the art bank, RAM, the fixed bank), each image's bytes
(rows x bytes a row) once per direction it is drawn in (normal and
mirrored), per scene and for the art bank over all scenes.
    python probes/blitcensus.py work/analysis/bcs-s0 ...
"""
import sys
from collections import defaultdict

def load(d):
    out = []
    for ln in open(d + "/blitcensus.log"):
        p = ln.split()
        if p[0] == "fighter":
            continue
        kind, where, src, rows, w, mode, uses, flips = p
        out.append((kind, where, int(src, 16), int(rows), int(w), mode, int(uses), int(flips)))
    return out

runs = {d.rsplit("-s", 1)[-1]: load(d) for d in sys.argv[1:]}
art = defaultdict(set)
print("%-6s %-8s %6s %8s %8s %6s" % ("scene", "where", "images", "bytes", "mirr+", "caps"))
for sc, recs in sorted(runs.items()):
    by = defaultdict(lambda: defaultdict(set))
    caps = defaultdict(int)
    for kind, where, src, rows, w, mode, uses, flips in recs:
        if "/ft" in kind:          # (the fighters' parts: their bank isn't chosen yet, so
            continue               # their headers read here are another bank's)
        d = "M" if kind.startswith("M") else "N"
        by[where][(src, rows, w)].add(d)
        if "/cap" in kind:
            caps[where] += 1
        if where == "b6":
            art[(src, rows, w)].add(d)
    for where, imgs in sorted(by.items()):
        base = sum(r * w for (s, r, w) in imgs)
        both = sum(r * w for (s, r, w), ds in imgs.items() if len(ds) == 2)
        only_m = sum(r * w for (s, r, w), ds in imgs.items() if ds == {"M"})
        print("%-6s %-8s %6d %8d %8d %6d" % (sc, where, len(imgs), base, both, caps[where]))
tot = sum(r * w for (s, r, w) in art)
both = sum(r * w for (s, r, w), ds in art.items() if len(ds) == 2)
print("art bank over all scenes: %d images, %d bytes, +%d for images drawn both ways" % (len(art), tot, both))
