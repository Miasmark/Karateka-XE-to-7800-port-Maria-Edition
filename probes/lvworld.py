"""A scrolling level's worlds (FINDINGS "Levels 2-4 without the blitter"):
from p7800-l1cap.lua logs and the state record, each picture of SCENE by its
structure ($4C) and view (V = 4 x $52 + $50 / 2): the views' range per
structure, and each blit (image, kind, mode, row) and fill with its places in
world x (screen x + V) per structure and the pictures it is in.
    python probes/lvworld.py SCENE LOG:STATE.BIN [...]"""
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from l1worldlist import state_mode, signed      # noqa: E402

scene = int(sys.argv[1])
views = defaultdict(list)
blits = defaultdict(Counter)
bpics = defaultdict(set)
fills = defaultdict(Counter)
dims = {}
for arg in sys.argv[2:]:
    log, st = arg.rsplit(":", 1)
    modes = state_mode(st)
    pend = []
    for line in open(log):
        p = line.split()
        if p[0] == "I":
            d = bytes.fromhex(p[3])
            dims.setdefault((int(p[1], 16), int(p[2])), (d[0], d[1]))
            continue
        if p[0] != "P":
            pend.append(p)
            continue
        n = int(p[1])
        if modes.get(n, (0, 0, 0))[1] != scene:
            pend = []
            continue
        z = bytes.fromhex(p[3])
        V, s4c = 4 * z[0] + z[1] // 2, z[2]
        views[s4c].append(V)
        for q in pend:
            if q[0] == "B":
                src, bk = int(q[7], 16), int(q[8])
                rows, w = dims.get((src, bk), dims.get(next((k for k in dims if k[0] == src), None), (0, 1)))
                col = signed(int(q[4]))
                if q[2] in ("AR", "MR"):
                    col -= w - 1
                x = 4 * col + (int(q[6]) >> 1)
                k = (s4c, src, bk, q[2], q[3], int(q[5]))
                blits[k][x + V] += 1
                bpics[k].add(n)
            elif q[0] == "F" and q[10] == "0":
                c0, c1 = int(q[3]), int(q[4])
                fills[(s4c, q[2], int(q[6]), int(q[5]), q[8], q[9])][(4 * c0 + V, 4 * c1 + V)] += 1
        pend = []
for s in sorted(views):
    v = views[s]
    print("structure %d: %d pictures, V %d-%d, %d views" % (s, len(v), min(v), max(v), len(set(v))))
print("--- blits: structure image bank kind mode row | draws places pictures | top world places")
for k in sorted(blits, key=lambda k: (k[0], -sum(blits[k].values()))):
    c = blits[k]
    print("%d %04X b%d %-2s %s r%3d | %5d %4d %4d | %s" % (k + (sum(c.values()), len(c), len(bpics[k]),
          " ".join("%d:%d" % xm for xm in c.most_common(6)))))
print("--- fills: structure kind top bottom v02 v12 | draws places | top world places")
for k in sorted(fills, key=lambda k: (k[0], -sum(fills[k].values()))):
    c = fills[k]
    print("%d %s %d %d %s %s | %5d %4d | %s" % (k + (sum(c.values()), len(c),
          " ".join("%d-%d:%d" % (a, b, m) for (a, b), m in c.most_common(5)))))
