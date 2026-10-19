"""Compare the snapshots of two runs (run7800.sh ... SNAPS=1), in order.

    python probes/snapdiff.py work/analysis/snap1new work/analysis/snap1old [--band Y0 Y1]

Prints each pair's differing box; with --band, also whether rows Y0-Y1 of
the picture (screen pixels) match, and writes the pair's band side by side.
"""
import argparse
import glob
import os

from PIL import Image, ImageChops


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--band", nargs=2, type=int)
    o = ap.parse_args()
    na = sorted(glob.glob(os.path.join(o.a, "**", "*.png"), recursive=True))
    nb = sorted(glob.glob(os.path.join(o.b, "**", "*.png"), recursive=True))
    for i, (a, b) in enumerate(zip(na, nb)):
        A, B = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
        line = "%s %s: differ in %s" % (os.path.basename(a), A.size, ImageChops.difference(A, B).getbbox())
        if o.band:
            y0, y1 = o.band
            ba, bb = A.crop((0, y0, A.size[0], y1)), B.crop((0, y0, B.size[0], y1))
            line += "; band %d-%d %s" % (y0, y1, "same" if ImageChops.difference(ba, bb).getbbox() is None else "DIFFERS")
            out = Image.new("RGB", (A.size[0], 2 * (y1 - y0) + 4))
            out.paste(ba, (0, 0))
            out.paste(bb, (0, y1 - y0 + 4))
            out.save(os.path.join(o.a, "band%d.png" % i))
        print(line)


if __name__ == "__main__":
    main()
