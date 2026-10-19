"""Akuma's and the hawk's poses (FINDINGS "Akuma and the hawk pre-cut at
load"): from probes/tmp-aklog.lua's logs (each blit AkCap records: picture,
image, flags, column, row, shift), the poses FtEmitAk draws: a mask and the
sprite after it at the same place, kind, shift and width are one (a pair:
the sprite's image and flags, the mask's image at $14/$15, as FtAkPair
makes them); any other blit alone. To port/akposes.txt:
    P scene image mask flags row   (seen)
(mask 0000: none; scene 3 the hawk's, flags bit 4; 4 Akuma's).

    python probes/akposes.py LOG [LOG ...]"""
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import l1scene7800 as LS        # noqa: E402


def main():
    get = LS.cart_get(os.path.join(HERE, "..", "work", "karateka7800.a78"))
    poses = Counter()
    for log in sys.argv[1:]:
        recs = defaultdict(list)
        for l in open(log):
            n, img, fl, col, row, sh = l.split()
            recs[int(n)].append((int(img, 16), int(fl, 16), int(col), int(row), int(sh)))
        for n, rs in recs.items():
            i = 0
            while i < len(rs):
                img, fl, col, row, sh = rs[i]
                sc = 3 if fl & 0x10 else 4
                key = (sc, img, 0, fl, row)
                if fl & 0x20 and i + 1 < len(rs):
                    i2, f2, c2, r2, s2 = rs[i + 1]
                    if (not f2 & 0x20 and (f2 ^ fl) & 0xC0 == 0 and (c2, r2, s2) == (col, row, sh)
                            and get(sc, i2 + 1) == get(sc, img + 1)):
                        key = (sc, i2, img, f2, row)
                        i += 1
                poses[key] += 1
                i += 1
    path = os.path.join(HERE, "..", "port", "akposes.txt")
    with open(path, "w", newline="\n") as f:
        f.write("# Akuma's (scene 4) and the hawk's (scene 3) poses (probes/akposes.py from %s)\n"
                "# P scene image mask flags row   (seen)\n" % ", ".join(sys.argv[1:]))
        for k in sorted(poses):
            f.write("P %d %04X %04X %02X %d   %d\n" % (k + (poses[k],)))
    print("%d poses to %s" % (len(poses), path))


if __name__ == "__main__":
    main()
