"""The game's own buffer at pictures of a p7800-l1cap.lua log, to PNGs (rows
65-145, 4x): python probes/capshow.py LOG OUTDIR N [N ...]"""
import os
import sys
from PIL import Image

R0, R1 = 65, 146
PAL = [(0, 0, 0), (230, 150, 120), (110, 160, 240), (240, 240, 240)]


def main():
    log, out = sys.argv[1], sys.argv[2]
    want = {int(x) for x in sys.argv[3:]}
    for line in open(log):
        p = line.split()
        if p[0] != "P" or int(p[1]) not in want:
            continue
        n = int(p[1])
        z = bytes.fromhex(p[3])
        real = bytes.fromhex(p[5] if p[2] == "A" else p[7])
        im = Image.new("RGB", (160, R1 - R0))
        for r in range(R1 - R0):
            for x in range(160):
                im.putpixel((x, r), PAL[(real[r * 40 + (x >> 2)] >> (6 - 2 * (x & 3))) & 3])
        im.resize((640, 4 * (R1 - R0)), Image.NEAREST).save(
            os.path.join(out, "cap_%d_V%d.png" % (n, 4 * z[0] + z[1] // 2)))


if __name__ == "__main__":
    main()
