"""Levels 2-4 without the blitter and without a bitmap, the model (FINDINGS
"Levels 2-4 without the blitter"): every blit and every fill (but a
fighter-box erase) an object, in the game's drawing order, against the
game's own buffers in p7800-l1cap.lua logs.

Each buffer's objects: a blit, or a fill (a span: its rows and byte columns,
its value or two-row pattern), appended; an object wholly covered by a later
opaque one (a fill, a stored blit at whole bytes) is dropped; a blit drawn
again (the same image, kind, mode and row) moves (ROOMS: wherever; else only
the same place, and a picture whose view changed drops the blits not drawn
in it, as level 1's rule; fills stay: they are fixed on the screen); a clear
empties it; a copy copies the other's. A picture: black, then the objects
(a fill and a store opaque, an OR's non-zero pixels, an AND mask ANDed in).
Prints the pictures that differ and the most objects a buffer and a zone row
held.

    python probes/spanmodel.py SCENE LOG:STATE.BIN [--rooms] [--show N --png OUT]"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from l1worldlist import state_mode, signed      # noqa: E402

R0, R1 = 65, 146
PRUNE = "--noprune" not in sys.argv    # (a fill painting what is there already: none)


class Img(object):
    def __init__(self, hexs):
        d = bytes.fromhex(hexs)
        self.rows, self.w, self.d = d[0], d[1], d[2:]

    def px(self, r, x, mir):
        if mir:
            x = 4 * self.w - 1 - x
        b = self.d[r * self.w + (x >> 2)]
        return (b >> (6 - 2 * (x & 3))) & 3


def run(scene, log, st, rooms, show=None, png=None):
    modes = state_mode(st)
    imgs = {}
    bufs = {"A": [], "B": []}
    drawn = {"A": set(), "B": set()}
    view = {"A": None, "B": None}
    pend, out = [], []

    def img(src, bk):
        return imgs.get((src, bk)) or next(v for kk, v in imgs.items() if kk[0] == src)

    def box(o):
        """(row0, row1, x0, x1, opaque) of an object"""
        if o[0] == "F":
            return o[2], o[3], 4 * o[4], 4 * o[5], True
        src, bk, kind, row, mode, x = o[1:]
        im = img(src, bk)
        return row, row + im.rows, x, x + 4 * im.w, (0 < mode < 0x80 and x % 4 == 0)

    def same_fill(f, g):
        """g paints what f does over f's rows (the same values in the same
        rows' phase) and holds f's rectangle"""
        if not (g[2] <= f[2] and f[3] <= g[3] and g[4] <= f[4] and f[5] <= g[5]):
            return False
        return all((f[6] if (f[1] == "rect" or (f[8] - 1 - r) % 2 == 0) else f[7]) ==
                   (g[6] if (g[1] == "rect" or (g[8] - 1 - r) % 2 == 0) else g[7]) for r in range(f[2], f[3]))

    def redundant(b, o):
        """a fill painting what is there already: over nothing (black, it
        paints 0), or over a fill of the same that holds it with nothing
        between them"""
        r0, r1, x0, x1, _ = box(o)
        for p in reversed(b):
            q0, q1, y0, y1, _ = box(p)
            if q0 < r1 and r0 < q1 and y0 < x1 and x0 < y1:
                return p[0] == "F" and same_fill(o, p)
        return o[1] == "rect" and o[6] == 0 or (o[6] == 0 and o[7] == 0)

    def add(b, o):
        if PRUNE and o[0] == "F" and redundant(b, o):
            return
        r0, r1, x0, x1, opq = box(o)
        if opq:
            keep = []
            for p in b:
                q0, q1, y0, y1, _ = box(p)
                if not (r0 <= max(q0, R0) and min(q1, R1) <= r1 and x0 <= max(y0, 0) and min(y1, 160) <= x1):
                    keep.append(p)
            b[:] = keep
        b.append(o)

    for line in open(log):
        p = line.split()
        if p[0] == "I":
            imgs[(int(p[1], 16), int(p[2]))] = Img(p[3])
            continue
        if p[0] != "P":
            pend.append(p)
            continue
        n, dr = int(p[1]), p[2]
        z = bytes.fromhex(p[3])
        V = 4 * z[0] + z[1] // 2
        for q in pend:
            k = q[0]
            if k == "C":
                bufs[q[1]] = []
            elif k == "K":
                dst = q[1]
                bufs[dst] = list(bufs["B" if dst == "A" else "A"])
            elif k == "B":
                src, bk = int(q[7], 16), int(q[8])
                im = img(src, bk)
                col = signed(int(q[4]))
                if q[2] in ("AR", "MR"):
                    col -= im.w - 1
                x = 4 * col + (int(q[6]) >> 1)
                o = ("B", src, bk, q[2] in ("M", "MR"), int(q[5]), int(q[3], 16), x)
                b = bufs[q[1]]
                if rooms:
                    b[:] = [p2 for p2 in b if not (p2[0] == "B" and p2[1:6] == o[1:6])]
                elif o in b:
                    b.remove(o)
                add(b, o)
                drawn[q[1]].add(o)
            elif k == "F" and q[10] == "0":
                c0, c1, bot, top = int(q[3]), int(q[4]), int(q[5]), int(q[6])
                if top >= 0xDD:
                    top = 0
                if c0 >= 40:
                    if c1 >= 41:
                        continue
                    c0 = 0
                c1 = min(c1, 40)
                top, bot = max(top, R0), min(bot, R1)
                if top >= bot or c0 >= c1:
                    continue
                o = ("F", q[2], top, bot, c0, c1, int(q[8], 16), int(q[9], 16), int(q[5]))
                add(bufs[q[1]], o)
        pend = []
        if not rooms and view[dr] is not None and view[dr] != V:
            bufs[dr] = [o for o in bufs[dr] if o[0] == "F" or o in drawn[dr]]
        view[dr] = V
        drawn[dr] = set()
        if modes.get(n, (0, 0, 0))[1] != scene:
            continue
        pic = [[0] * 160 for r in range(R1 - R0)]
        zone_n = Counter()
        for o in bufs[dr]:
            r0, r1, x0, x1, opq = box(o)
            for z0 in range(R0, R1, 8):
                if r0 < z0 + 8 and r1 > z0 and x1 > 0 and x0 < 160:
                    zone_n[z0] += 1 + (o[0] == "F" and (o[5] - o[4]) > 31)
            if o[0] == "F":
                kind, top, bot, c0, c1, v02, v12, obot = o[1:]
                for r in range(top, bot):
                    v = v02 if (kind == "rect" or (obot - 1 - r) % 2 == 0) else v12
                    for c in range(c0, c1):
                        for qq in range(4):
                            pic[r - R0][4 * c + qq] = (v >> (6 - 2 * qq)) & 3
                continue
            src, bk, mir, row, mode, x = o[1:]
            im = img(src, bk)
            for rr in range(im.rows):
                r = row + rr
                if not R0 <= r < R1:
                    continue
                for xx in range(4 * im.w):
                    sx = x + xx
                    if not 0 <= sx < 160:
                        continue
                    v = im.px(rr, xx, mir)
                    if mode >= 0x80:
                        pic[r - R0][sx] &= v
                    elif mode == 0:
                        pic[r - R0][sx] |= v
                    else:
                        pic[r - R0][sx] = v
        real = bytes.fromhex(p[5] if dr == "A" else p[7])
        diff = sum(1 for r in range(R1 - R0) for c in range(160)
                   if (real[r * 40 + (c >> 2)] >> (6 - 2 * (c & 3))) & 3 != pic[r][c])
        out.append((n, diff, len(bufs[dr]), max(zone_n.values() or [0])))
        if png and show == n:
            from PIL import Image
            PAL = [(0, 0, 0), (230, 150, 120), (110, 160, 240), (240, 240, 240)]
            im = Image.new("RGB", (160, 2 * (R1 - R0) + 4), (255, 0, 255))
            for r in range(R1 - R0):
                for c in range(160):
                    im.putpixel((c, r), PAL[pic[r][c]])
                    im.putpixel((c, R1 - R0 + 4 + r), PAL[(real[r * 40 + (c >> 2)] >> (6 - 2 * (c & 3))) & 3])
            im.resize((640, im.height * 4), Image.NEAREST).save(png)
    return out


def main():
    scene = int(sys.argv[1])
    rooms = "--rooms" in sys.argv
    show = int(sys.argv[sys.argv.index("--show") + 1]) if "--show" in sys.argv else None
    png = sys.argv[sys.argv.index("--png") + 1] if "--png" in sys.argv else None
    for arg in sys.argv[2:]:
        if ":" not in arg or arg.startswith("--") or arg == png:
            continue
        log, st = arg.rsplit(":", 1)
        res = run(scene, log, st, rooms, show, png)
        bad = [r for r in res if r[1]]
        print("%s: %d pictures, %d differ; most objects a buffer %d, a zone %d (median %d)" % (
            log, len(res), len(bad), max(r[2] for r in res), max(r[3] for r in res),
            sorted(r[3] for r in res)[len(res) // 2]))
        print("   pixels/100:", dict(sorted(Counter(min(r[1] // 100, 10) for r in bad).items())))
        print("   first:", [r[:2] for r in bad[:15]])


if __name__ == "__main__":
    main()
