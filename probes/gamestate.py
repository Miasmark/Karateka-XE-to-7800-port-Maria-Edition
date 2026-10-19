"""The game's own state in the port's RAM (FINDINGS "Replaying a recording on
another build"): its zero page through the build's map (work/karateka7800.zp)
and the RAM the port carves out for it (layout7800 CARVE_ENGINE2,
CARVE_COMMON, CARVE_SDATA), one hex address a line, to work/gamestate.txt.
Our display code doesn't touch any of it, so forcing it at each flip makes
another build draw the recorded game.

    python probes/gamestate.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import layout7800 as L    # noqa: E402

out = set()
for line in open(os.path.join(HERE, "..", "work", "karateka7800.zp")):
    f = line.split()
    if len(f) == 2:
        out.add(int(f[1], 16))
for lo, hi, at in L.CARVE_ENGINE2 + L.CARVE_COMMON:
    out.update(range(at, at + hi - lo))
for sc, lst in L.CARVE_SDATA.items():
    for lo, hi, at in lst:
        if hi - lo <= 16:              # the flags; not the copied sprites
            out.update(range(at, at + hi - lo))
with open(os.path.join(HERE, "..", "work", "gamestate.txt"), "w") as o:
    for a in sorted(out):
        o.write("%04X\n" % a)
print(len(out), "addresses")
