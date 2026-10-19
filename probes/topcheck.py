"""The buffers' top rows as MARIA objects, checked against the bitmap itself:
replays probes/p7800-toplog.lua's log (run with DUMPTOP=1) per buffer -- a
draw above the cut adds a piece unless wholly off the screen (and removes any wholly under it: the game's
blits are opaque rectangles; the column routine's calls add a piece every 2
rows), a fill removes the pieces it covers (whole:
any piece covered only in part is reported), a full clear empties the list,
a copy copies it -- and at every flip renders the shown buffer's rows 0 to
CUT-1 as objects: the background colour SKY, each piece converted (its
colour SKY transparent; when SKY is not 0, its colour 0 an opaque black),
mirrored pieces (MR) reversed and placed with their left edge at
4 x ($05 - width + 1) + shift. Compared with the dump of the buffer shown.
    python probes/topcheck.py toplog.log SKY [CUT]
(the images' bytes from the original's asset logs, work/analysis/as-*/; SKY
2 for level 1, 0 for level 2.) Rows the port's level-1 column routine draws (the posts'
middle pieces, not blits) are counted apart (POSTROWS).
"""
import sys

import collections
import glob
import os

LOG, SKY = sys.argv[1], int(sys.argv[2])
CUT = int(sys.argv[3]) if len(sys.argv) > 3 else 45
# SCENES=1,6: compare only the pictures shown in these scenes ($D0 at the flip)
SCENES = {int(x) for x in os.environ["SCENES"].split(",")} if os.environ.get("SCENES") else None
ASSETS = glob.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "work", "analysis", "as-*", "assetlog.log"))
POSTROWS = range(41, 45)
UNKNOWN = collections.Counter()
BADPIC, BADROW = collections.Counter(), collections.Counter()
OPAQUE_BLACK = 4


def images(paths):
    """the images' bytes, by the port's address, rows and width (an address
    holds different images in different levels)"""
    out = {}
    for path in paths:
        for line in open(path):
            p = line.split()
            if p[0] == 'I':
                b = bytes.fromhex(p[5])
                out.setdefault((int(p[2], 16) + 0x4000, b[0], b[1]), b)
    return out


def pix(img):
    rows, width = img[0], img[1]
    return rows, width, [[(img[2 + r * width + c // 4] >> (6 - 2 * (c % 4))) & 3 for c in range(4 * width)]
                         for r in range(rows)]


def place(kind, x, width):
    """the piece's left pixel and whether mirrored"""
    c, s = x // 4, x % 4
    if c >= 128:
        c -= 256
    if kind.startswith('M'):
        return 4 * (c - width + 1) + s, True
    return 4 * c + s, False


def main():
    imgs = images(ASSETS)
    pieces = {'A': [], 'B': []}
    bg = {'A': 0, 'B': 0}           # each buffer's top: black until a fill across it
    shown, here = None, False
    pics = bad_top = bad_post = partial = 0
    first = []
    for line in open(LOG):
        p = line.split()
        if not p:
            continue
        if p[0] == 'C':
            pieces[p[2]] = []
            bg[p[2]] = 0
        elif p[0] == 'K':
            pieces[p[2]] = list(pieces['B' if p[2] == 'A' else 'A'])
            bg[p[2]] = bg['B' if p[2] == 'A' else 'A']
        elif p[0] in ('B', 'L'):
            b, kind, src, x, top = p[2], p[3], int(p[4], 16), int(p[7]), int(p[8])
            if (src, int(p[5]), int(p[6])) not in imgs:
                UNKNOWN[(src, int(p[5]), int(p[6]))] += 1     # (an image the asset logs lack:
                continue                                       # counted, not drawn)
            rows, width, px = pix(imgs[(src, int(p[5]), int(p[6]))])
            left, mirrored = place(kind, x, width)
            if mirrored:
                px = [r[::-1] for r in px]
            tops = [top]
            if p[0] == 'L':                 # the column routine: 2 rows down each time
                limit, tops, t = int(p[9]), [], top
                while True:
                    t += 2
                    tops.append(t)
                    if t >= limit:
                        break
            if max(left, 0) > min(left + 4 * width - 1, 159):
                continue                    # wholly off the screen: the blitter draws nothing
            for t in tops:
                if t >= CUT:
                    break
                # the blit is an opaque rectangle: pieces wholly under it are gone
                pieces[b] = [q for q in pieces[b] if not (left <= q[0] and q[0] + 4 * q[3] <= left + 4 * width
                                                          and t <= q[1] and q[1] + q[2] <= t + rows)]
                pieces[b].append((left, t, rows, width, px, ()))
        elif p[0] == 'F':
            b, c0, c1, top, bot = p[2], int(p[4]), int(p[5]), int(p[6]), int(p[7])
            if c0 == 0 and c1 >= 40 and top <= 0 and bot >= CUT - 1:
                bg[b] = int(p[8], 16) & 3       # the whole top filled: its colour
            fx0, fx1, ft = 4 * c0, 4 * c1 - 1, max(top, 0)
            keep = []
            for pc in pieces[b]:
                left, t, rows, width, px, gone = pc
                x0, x1, b0, b1 = max(left, 0), min(left + 4 * width - 1, 159), t, min(t + rows - 1, CUT - 1)
                if x0 > x1 or b0 > b1 or x1 < fx0 or x0 > fx1 or b1 < ft or b0 > bot:
                    keep.append(pc)
                elif fx0 <= x0 and x1 <= fx1 and ft <= b0 and b1 <= bot:
                    pass
                else:
                    partial += 1
                    pc = (left, t, rows, width, px, gone + ((fx0, fx1, ft, bot),))   # its pixels there: gone
                    if os.environ.get("SHOWPARTIAL") and partial <= 8:
                        print("   partial: piece x %d-%d rows %d-%d (%dx%d) by fill cols %d-%d rows %d-%d" % (
                            left, left + 4 * width - 1, t, t + rows - 1, rows, width, c0, c1, top, bot))
                    keep.append(pc)
            pieces[b] = keep
        elif p[0] == 'P':
            shown = p[3]
            here = SCENES is None or (len(p) > 4 and int(p[4]) in SCENES)
        elif p[0] == 'D' and shown and here:
            pics += 1
            h = p[1]
            bm = [[(int(h[2 * (r * 40 + c // 4):2 * (r * 40 + c // 4) + 2], 16) >> (6 - 2 * (c % 4))) & 3
                   for c in range(160)] for r in range(CUT)]
            ob = [[bg[shown]] * 160 for _ in range(CUT)]
            for left, t, rows, width, px, gone in pieces[shown]:
                for r in range(rows):
                    y = t + r
                    if not 0 <= y < CUT:
                        continue
                    for k, v in enumerate(px[r]):
                        X = (left + k) & 0xFF        # MARIA wraps at 256
                        if X >= 160 or v == SKY:
                            continue
                        if any(g[0] <= X <= g[1] and g[2] <= y <= g[3] for g in gone):
                            continue
                        ob[y][X] = OPAQUE_BLACK if v == 0 else v
            for y in range(CUT):
                row = [0 if v == OPAQUE_BLACK else v for v in ob[y]]
                if row != bm[y]:
                    if y in POSTROWS:
                        bad_post += 1
                        if os.environ.get("SHOWPOST") and bad_post <= 6:
                            xs = [X for X in range(160) if row[X] != bm[y][X]]
                            print("   post rows: picture %d buffer %s row %d: x %s; objects %s bitmap %s" % (
                                pics, shown, y, xs[:12], [row[X] for X in xs[:12]], [bm[y][X] for X in xs[:12]]))
                    else:
                        bad_top += 1
                        BADPIC[pics] += 1
                        BADROW[y] += 1
                        if len(first) < 6:
                            xs = [X for X in range(160) if row[X] != bm[y][X]]
                            first.append((pics, shown, y, xs[0], xs[-1], len(xs)))
    print("%d pictures: rows 0-%d differing %d; rows %d-%d (the column routine's) differing %d; "
          "pieces erased only in part: %d" % (pics, POSTROWS[0] - 1, bad_top, POSTROWS[0], POSTROWS[-1], bad_post, partial))
    for f in first:
        print("   picture %d buffer %s row %d: x %d-%d, %d pixels" % f)
    if BADPIC:
        print("   differing pictures: %d; rows: %s" % (len(BADPIC), " ".join("%d:%d" % kv for kv in sorted(BADROW.items()))))
        print("   pictures (picture:rows): " + " ".join("%d:%d" % kv for kv in sorted(BADPIC.items())[:40]))
    if UNKNOWN:
        print("   images the asset logs lack (not drawn): %s" % ", ".join("$%04X %dx%d x%d" % (k[0], k[1], k[2], n)
                                                                         for k, n in UNKNOWN.most_common(6)))


main()
