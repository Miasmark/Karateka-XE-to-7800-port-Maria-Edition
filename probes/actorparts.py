"""The actors' images in the fighters' band, from the original's draw logs
(probes/xe-bandlog.lua runs, work/analysis/bl-s*), grouped by the routine
that draws them: how (mode $0F: 0 OR, a sprite over what is there;
negative AND, a mask; else store, opaque), how many, their bytes, and the
colours the OR and store images use (FINDINGS "The fighters' parts: masks
and colours").

    python probes/actorparts.py work/analysis/bl-s1 [...]"""
import collections
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import dis as D     # noqa: E402

groups = collections.defaultdict(lambda: {"imgs": set(), "draws": 0})
for d in sys.argv[1:]:
    for line in open(os.path.join(d, "bandlog.log")):
        t = line.split()
        if t[0] != "B":
            continue
        f, flip, sc, kind, src, bank, rows, width, caller, col, top, shift, mode, buf = t[1:]
        r0 = int(top) - 35
        if r0 + int(rows) < 79 or r0 > 128:          # (the actors' band)
            continue
        mode = int(mode)
        how = "mask" if mode < 0 else ("sprite" if mode == 0 else "store")
        g = groups[(int(sc), caller, how)]
        g["imgs"].add((int(src, 16), int(bank)))
        g["draws"] += 1
mem = {s: D.memory(s) for s in (0, 1, 2, 3, 4, 6)}
for (sc, caller, how), g in sorted(groups.items()):
    m = mem[sc]
    used, nbytes = collections.Counter(), 0
    for a, bank in g["imgs"]:
        r, w = m[a], m[a + 1]
        nbytes += r * w
        for i in range(r * w):
            b = m[a + 2 + i]
            for k in range(4):
                used[(b >> (6 - 2 * k)) & 3] += 1
    print("scene %d %s %-6s %3d images %5d bytes %5d draws colours %s"
          % (sc, caller, how, len(g["imgs"]), nbytes, g["draws"], dict(sorted(used.items()))))
