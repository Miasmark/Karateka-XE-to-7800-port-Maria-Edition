"""Compare the snapshots of two runs, in order, by differing pixels.

    python probes/snapcount.py work/analysis/ck1 work/analysis/ie1sa [--over 300] [--list]

Prints how many pairs differ in more than --over pixels (the fighters' own
small differences, FINDINGS "The fighters as objects: step 2", stay under
it) and, with --list, each such pair's count and differing box.
"""
import argparse
import glob
import os

from PIL import Image, ImageChops


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--over", type=int, default=300)
    ap.add_argument("--list", action="store_true")
    o = ap.parse_args()
    na = sorted(glob.glob(os.path.join(o.a, "**", "*.png"), recursive=True))
    nb = sorted(glob.glob(os.path.join(o.b, "**", "*.png"), recursive=True))
    over = 0
    for a, b in zip(na, nb):
        d = ImageChops.difference(Image.open(a).convert("RGB"), Image.open(b).convert("RGB"))
        n = sum(1 for p in d.getdata() if p != (0, 0, 0))
        if n > o.over:
            over += 1
            if o.list:
                print("%s %d %s" % (os.path.basename(a), n, d.getbbox()))
    print("%d of %d over %d" % (over, min(len(na), len(nb)), o.over))


main()
