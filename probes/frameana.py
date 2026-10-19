"""Per-frame screenshots (probes/p7800-showdraw.lua) of level 2 checked for
two artefacts: the floor not its colour (the band's colour change lost) and
a picture with fewer fighter pixels than the frames around it (a buffer shown
while the game redraws it).

    python probes/frameana.py work/analysis/<run> [floor_x floor_y]
Prints each frame: its flip, the floor pixel's colour, the fighters' band's
lit pixels; flags "FLOOR" (a colour other than the run's commonest there) and
"DROP" (under half its neighbours' lit pixels)."""
import collections
import os
import sys

from PIL import Image

d = sys.argv[1]
fx, fy = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (10, 160)
log = [ln.split() for ln in open(os.path.join(d, "showdraw.log"))]
rows = []
for frame, flip, k in log:
    im = Image.open(os.path.join(d, "a7800", "%04d.png" % int(k))).convert("RGB")
    band = im.crop((0, 110, 320, 158))
    lit = sum(1 for p in band.getdata() if p != (0, 0, 0))
    rows.append((int(frame), int(flip), im.getpixel((fx, fy)), lit))
common = collections.Counter(r[2] for r in rows).most_common(1)[0][0]
for i, (frame, flip, col, lit) in enumerate(rows):
    near = [rows[j][3] for j in (i - 1, i + 1) if 0 <= j < len(rows)]
    flags = []
    if col != common:
        flags.append("FLOOR")
    if near and lit < 0.5 * min(near):
        flags.append("DROP")
    print(frame, flip, col, lit, " ".join(flags))
