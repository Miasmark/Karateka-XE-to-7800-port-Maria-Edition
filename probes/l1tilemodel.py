"""Level 1 without the blitter, model 6: tiles plus objects, scrolled the
Midnight Mutants way (FINDINGS "Level 1 without the blitter: tiles plus
objects"). Replays p7800-l1cap.lua's log. Layers, bottom up:
  - each row's background colour: the full-width fills, and the rails
    ($AA11, the same all along the row);
  - the screen tiles: the other fills and the pieces fixed on screen (the
    mountain's base $A9B8/$A9E2, $AB4A), whole bytes on the screen's grid;
  - the fence's posts ($AA23, plain and mirrored) as objects: this
    picture's; a fill over one drops it;
  - the world tiles: every other blit, on the world grid (x - V), scrolled
    with the view; a pixel equal to its row's background is transparent.
A tile is 4 pixels by its zone's rows. A write into a tile composes with
what that picture already put there (the pieces a picture draws together:
the build can render them together); a tile from an earlier picture is
replaced whole. When a buffer's view (V) changes, its tiles start empty
(the game redraws all it shows). $AA31 (the posts' eraser) is dropped.
Compared with the real buffers; the distinct tiles counted.

    python probes/l1tilemodel.py LOG [--show N] [--pic N] [--zones a,b,c,...]"""
import os
import sys
from collections import Counter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import l1model as L

R0, R1 = 65, 146
ZEDGES = [int(x) for x in sys.argv[sys.argv.index("--zones") + 1].split(",")] if "--zones" in sys.argv \
    else list(range(R0, R1, 8)) + [R1]
ZONES = list(zip(ZEDGES, ZEDGES[1:]))
ZOF = {r: zi for zi, (a, b) in enumerate(ZONES) for r in range(a, b)}
SCREEN = {0xA9B8, 0xA9E2}           # ($AB4A, the torii's beam drawn from x 0, is the torii's: world)
FENCE = {0xAA23}
DROP = {0xAA31}
RAILS = 0xAA11


class Buf:
    def __init__(self):
        self.bg = [bytearray(40) for _ in range(R1 - R0)]
        self.scr = {}                   # (row, x) -> pixel, with scrpic[(zone, col)]
        self.scrpic = {}
        self.fence = []
        self.fence_pic = -1
        self.world = {}                 # (row, wx) -> pixel, with wpic[(zone, wcol)]
        self.wpic = {}
        self.V = None
        self.placed = {}                # (SKIP) what is placed since the last reset: key -> (layer, x0, x1, r0, r1)

    def copy(self):
        b = Buf()
        b.bg = [bytearray(r) for r in self.bg]
        b.scr, b.scrpic = dict(self.scr), dict(self.scrpic)
        b.fence, b.fence_pic = list(self.fence), self.fence_pic
        b.world, b.wpic = dict(self.world), dict(self.wpic)
        b.V = self.V
        b.placed = dict(self.placed)
        return b


def bgpx(b, r, x):
    return L.px_get(b.bg[r - R0], x)


def scr_put(b, r, x, v, pic):
    """a screen-tile pixel: its tile emptied first if an earlier picture's"""
    cell = (ZOF[r], x >> 2)
    if b.scrpic.get(cell) != pic and not KEEPS:
        a, c = ZONES[cell[0]]
        for rr in range(a, c):
            for k in range(4):
                b.scr.pop((rr, 4 * cell[1] + k), None)
        b.scrpic[cell] = pic
    b.scr[(r, x)] = v


KEEPW = "--keepworld" in sys.argv          # (diagnosis: the world tiles compose across pictures)
KEEPS = "--keepscreen" in sys.argv
SKIP = "--skip" in sys.argv
TRANSP = "--transp" in sys.argv             # pieces as MARIA objects: their background-coloured pixels transparent                 # a draw already placed since the reset is not placed again


def world_put(b, r, wx, v, pic):
    cell = (ZOF[r], wx >> 2)
    if b.wpic.get(cell) != pic and not KEEPW:
        a, c = ZONES[cell[0]]
        for rr in range(a, c):
            for k in range(4):
                b.world.pop((rr, 4 * cell[1] + k), None)
        b.wpic[cell] = pic
    b.world[(r, wx)] = v


def render(b, V):
    fb = [bytearray(r) for r in b.bg]

    def put(r, x, v):
        if R0 <= r < R1 and 0 <= x < 160:
            L.px_set(fb[r - R0], x, v)
    for (r, x), v in b.scr.items():
        put(r, x, v)
    for img, mir, x0, row in b.fence:
        for r in range(img.rows):
            for k in range(4 * img.w):
                put(row + r, x0 + k, img.px(r, k, mir))
    for (r, wx), v in b.world.items():
        x = (wx + V) % 1024
        if x < 160 and v != bgpx(b, r, x):
            put(r, x, v)
    return fb


def place(img, kind, col, sh):
    c = L.signed(col) - (img.w - 1 if kind in ("AR", "MR") else 0)
    return 4 * c + (sh >> 1), kind in ("M", "MR")


def blit(bb, img, kind, mode, col, row, sh, V, pic, layer):
    x0, mir = place(img, kind, col, sh)
    for r in range(img.rows):
        y = row + r
        if not (R0 <= y < R1):
            continue
        for k in range(4 * img.w):
            x = x0 + k
            if not (0 <= x < 160):
                continue
            v = img.px(r, k, mir)
            if layer == "world":
                wx = (x - V) % 1024
                cell = (ZOF[y], wx >> 2)
                under = bb.world.get((y, wx), bgpx(bb, y, x)) if bb.wpic.get(cell) == pic else bgpx(bb, y, x)
            else:
                cell = (ZOF[y], x >> 2)
                under = bb.scr.get((y, x), bgpx(bb, y, x)) if bb.scrpic.get(cell) == pic else bgpx(bb, y, x)
            if mode == 0x00:
                v |= under
            elif mode >= 0x80:
                v &= under
            elif TRANSP and v == bgpx(bb, y, x):
                v = under               # (MARIA: a background-coloured pixel shows what is under it)
            if layer == "world":
                world_put(bb, y, (x - V) % 1024, v, pic)
            else:
                scr_put(bb, y, x, v, pic)


def main():
    path = sys.argv[1]
    show = int(sys.argv[sys.argv.index("--show") + 1]) if "--show" in sys.argv else 8
    pic = int(sys.argv[sys.argv.index("--pic") + 1]) if "--pic" in sys.argv else -1
    imgs = {}
    bufs = {"A": Buf(), "B": Buf()}
    st = Counter()
    wtiles = [set() for _ in ZONES]
    stiles = [set() for _ in ZONES]
    bads = []
    pend = []                           # the picture's events, until its P line gives V
    for line in open(path):
        p = line.split()
        t = p[0]
        if t == "I":
            imgs[int(p[1], 16)] = L.Img(bytes.fromhex(p[3]))
            continue
        if t != "P":
            pend.append(p)
            continue
        n, drawn = int(p[1]), p[2]
        z = bytes.fromhex(p[3])
        V = 4 * z[0] + z[1] // 2
        b0 = bufs[drawn]
        if b0.V != V:
            b0.world, b0.wpic, b0.scr, b0.scrpic, b0.V, b0.placed = {}, {}, {}, {}, V, {}
        for q in pend:
            if q[0] == "C":
                bufs[q[1]] = Buf()
                bufs[q[1]].V = V
            elif q[0] == "K":
                bufs[q[1]] = bufs["B" if q[1] == "A" else "A"].copy()
            elif q[0] == "B":
                bb = bufs[q[1]]
                src = int(q[7], 16)
                img = imgs[src]
                kind = q[2]
                mode, col, row, sh = int(q[3], 16), int(q[4]), int(q[5]), int(q[6])
                if src in DROP:
                    continue
                if src == RAILS:
                    L.blit(bb.bg, img, kind, mode, col, row, sh)
                    continue
                if src in FENCE:
                    if bb.fence_pic != n:
                        bb.fence, bb.fence_pic = [], n
                    x0, mir = place(img, kind, col, sh)
                    bb.fence.append((img, mir, x0, row))
                    continue
                lay = "screen" if src in SCREEN else "world"
                key = (src, kind, row, (place(img, kind, col, sh)[0] - (V if lay == "world" else 0)) % 1024)
                if SKIP and key in bb.placed:
                    continue
                x0 = place(img, kind, col, sh)[0]
                bb.placed[key] = (lay, x0, x0 + 4 * img.w, row, row + img.rows)
                blit(bb, img, kind, mode, col, row, sh, V, n, lay)
            elif q[0] == "L":
                bb = bufs[q[1]]
                src, col, row, sh, lim, entry, z52 = (int(q[2], 16), int(q[3]), int(q[4]), int(q[5]),
                                                      int(q[6]), q[8], int(q[9]))
                if src < 0xA000 or (entry == "68" and (z52 >= 0x80 or z52 < 0x14)):
                    continue
                key = ("L", src, row, lim, (place(imgs[src], "A", col, sh)[0] - V) % 1024)
                if SKIP and key in bb.placed:
                    continue
                x0 = place(imgs[src], "A", col, sh)[0]
                bb.placed[key] = ("world", x0, x0 + 4 * imgs[src].w, row, lim + imgs[src].rows)
                r0 = row
                while True:
                    r0 += 2
                    blit(bb, imgs[src], "A", 0x01, col, r0, sh, V, n, "world")
                    if r0 >= lim:
                        break
            elif q[0] == "F":
                bb = bufs[q[1]]
                kind = q[2]
                c0, c1, bot, top, v02, v12, nf = (int(q[3]), int(q[4]), int(q[5]), int(q[6]),
                                                  int(q[8], 16), int(q[9], 16), int(q[10]))
                if nf:
                    continue
                if top >= 0xDD:
                    top = 0
                if c0 >= 40:
                    if c1 >= 41:
                        continue
                    c0 = 0
                elif c1 >= 41:
                    c1 = 40
                nr = bot - top
                key = ("F", kind, c0, c1, top, bot, v02, v12)
                if SKIP and key in bb.placed:
                    continue
                full = c0 == 0 and c1 == 40
                # what it paints over may be drawn again
                for k2, (lay, a0, a1, b0_, b1_) in list(bb.placed.items()):
                    if b0_ < bot and top < b1_ and (full or (a0 < 4 * c1 and 4 * c0 < a1)):
                        del bb.placed[k2]
                bb.placed[key] = ("screen", 4 * c0, 4 * c1, top, bot)
                bb.fence = [f for f in bb.fence if not (f[2] < 4 * c1 and 4 * c0 < f[2] + 4 * f[0].w
                                                        and f[3] < bot and top < f[3] + f[0].rows)]
                for i in range(nr):
                    y = top + i
                    if not (R0 <= y < R1):
                        continue
                    v = v02 if (kind == "rect" or (nr - 1 - i) % 2 == 0) else v12
                    if c0 == 0 and c1 == 40:
                        bb.bg[y - R0] = bytearray([v] * 40)
                        for x in range(160):
                            bb.scr.pop((y, x), None)
                            bb.world.pop((y, (x - V) % 1024), None)
                        continue
                    for x in range(4 * c0, 4 * c1):
                        scr_put(bb, y, x, (v >> (6 - 2 * (x & 3))) & 3, n)
                        bb.world.pop((y, (x - V) % 1024), None)
        pend = []
        real = L.parse_dump(p[5] if drawn == "A" else p[7])
        if real[140 - 65][20] != 0x55:
            continue                    # (the cutscene's room: later)
        b = bufs[drawn]
        fb = render(b, V)
        d = sum(1 for r in range(R1 - R0) for x in range(160) if L.px_get(fb[r], x) != L.px_get(real[r], x))
        st["pics"] += 1
        for (zi, c) in b.wpic:
            a, e = ZONES[zi]
            wtiles[zi].add(tuple(b.world.get((r, 4 * c + k)) for r in range(a, e) for k in range(4)))
        for (zi, c) in b.scrpic:
            a, e = ZONES[zi]
            stiles[zi].add(tuple(b.scr.get((r, 4 * c + k)) for r in range(a, e) for k in range(4)))
        if d:
            st["bad"] += 1
            st["badpx"] += d
            bads.append((n, d))
            if len(bads) <= show:
                rows = [r + R0 for r in range(R1 - R0) if fb[r] != real[r]]
                print("pic %d buf %s: %d pixels differ, rows %s" % (n, drawn, d, rows[:14]))
        if n == pic:
            for r in range(R1 - R0):
                m = "".join(".123"[L.px_get(fb[r], x)] for x in range(160))
                q = "".join(".123"[L.px_get(real[r], x)] for x in range(160))
                print("%3d M %s\n%3d R %s %s" % (r + R0, m, r + R0, q, "" if m == q else "<<"))
    print(dict(st))
    runs = []
    for k, d in bads:
        if runs and k <= runs[-1][1] + 2:
            runs[-1][1] = k
            runs[-1][2] = max(runs[-1][2], d)
        else:
            runs.append([k, k, d])
    print("bad pictures (from-to, most pixels):", [tuple(r) for r in runs][:30])
    print("world tiles a zone:", [len(s) for s in wtiles], "all", sum(len(s) for s in wtiles))
    print("screen tiles a zone:", [len(s) for s in stiles], "all", sum(len(s) for s in stiles))


if __name__ == "__main__":
    main()
