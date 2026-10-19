"""Level 1 without the blitter: the shape inventory (FINDINGS "Level 1
without the blitter: the data and the plan") from p7800-l1cap.lua logs, to
port/l1shapes.txt (the build reads it):
    B src bank mir row mode   a blit (the 7800 address; mir 1: mirrored)
    L src bank mir row lim    a column of the column routine
Fills aren't listed (the build makes their characters). AA11 (the rails) and
AA31 (the fence posts' eraser) aren't shapes.

    python probes/l1inventory.py LOG [LOG ...]"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "port", "l1shapes.txt")


def main():
    bank, shapes = {}, Counter()
    for path in sys.argv[1:]:
        for line in open(path):
            p = line.split()
            if p[0] == "I":
                bank.setdefault(int(p[1], 16), int(p[2]))
            elif p[0] == "B":
                src = int(p[7], 16)
                if src in (0xAA11, 0xAA31):
                    continue
                shapes[("B", src, int(p[2] in ("M", "MR")), int(p[5]), int(p[3], 16))] += 1
            elif p[0] == "L":
                src, row, lim, entry, z52 = int(p[2], 16), int(p[4]), int(p[6]), p[8], int(p[9])
                if src < 0xA000:
                    continue
                mir = int(entry == "68" and (z52 >= 0x80 or z52 < 0x14))
                shapes[("L", src, mir, row, lim)] += 1
    # the column routine's own pieces (the second to the last of a column: it
    # draws them itself, or ScCol68's mirrored loop does) are the column's
    cols = [(k[1], k[2], k[3], k[4]) for k in shapes if k[0] == "L"]
    for k in list(shapes):
        if k[0] == "B" and any(k[1] == src and k[2] == mir and r0 < k[3] <= lim and (k[3] - r0) % 2 == 0
                               for src, mir, r0, lim in cols):
            del shapes[k]
    with open(OUT, "w", newline="\n") as o:
        o.write("# level 1's shapes below row 65 (probes/l1inventory.py from %s)\n"
                % ", ".join(os.path.relpath(p, os.path.join(HERE, "..")).replace("\\", "/") for p in sys.argv[1:]))
        o.write("# B src bank mir row mode | L src bank mir row lim   (seen)\n")
        for k in sorted(shapes, key=lambda k: (k[0], k[1], k[2], k[3], k[4])):
            o.write("%s %04X %d %d %d %d   %d\n" % (k[0], k[1], bank[k[1]], k[2], k[3], k[4], shapes[k]))
    print("%d shapes to %s" % (len(shapes), OUT))


if __name__ == "__main__":
    main()
