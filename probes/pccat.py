"""probes/p7800-pcsample.lua's log (TOPN=2000) summed by the fighters' work
(FINDINGS "The fighters as objects: speed"): python probes/pccat.py LOG"""
import re
import sys
from collections import Counter

GROUPS = [
    ("copy loops", r"^(FtRow|FtClr|FtCopy|FtRead)"),
    ("FtPlain cut", r"^FtPl(?!ace)"),
    ("FtLower", r"^FtLow"),
    ("FtUpper", r"^FtUp"),
    ("FtObj", r"^FtObj"),
    ("sort/place", r"^(FtSort|FtPlace)"),
    ("emit loop", r"^FtEmit"),
    ("band lists", r"^(BandW|BandRef)"),
    ("records/boxes/hooks", r"^(Fg|FRec|FtEnd|Mask|Flip0|BlitBank)"),
    ("top rows", r"^Top"),
    ("interrupts+colour", r"^(Nmi|Dli|ColTail|Vbi|G_L1148|G_L101F)"),
]
c, tot = Counter(), 0
for ln in open(sys.argv[1]):
    m = re.match(r"\s*(\d+)\s+[\d.]+%\s+(.*)", ln)
    if not m:
        continue
    n, k = int(m.group(1)), m.group(2).strip()
    tot += n
    name = k.split()[-1]
    g = next((g for g, rx in GROUPS if re.match(rx, name)), None)
    if g is None:
        g = ("engine part 2's blitter (cart RAM)" if k.startswith("RAM $7")
             else "fast fill and RAM code" if k.startswith("RAM $2") else "the game and the rest")
    c[g] += n
for g, n in c.most_common():
    print("%6.1f%%  %s" % (100 * n / tot, g))
