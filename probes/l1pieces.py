"""Level 1 without the blitter, model 2 (FINDINGS "Level 1 without the
blitter: the draws as pieces"): replays p7800-l1cap.lua's log as MARIA would
draw it. Each buffer keeps a background byte per row (set by full-width
fills; 0 after a clear) and a list of pieces in draw order (blits and the
other fills). A picture is the background, then each piece's pixels except
those equal to the row's background (transparent: MARIA's 160A colour 0 after
a palette remap). Compared with the real buffer at every picture from the
first full clear.

    python probes/l1pieces.py work/analysis/l1cap/l1cap.log [--rules a,b,c] [--show N]
"""
import sys
from collections import Counter
sys.path.insert(0, __file__.rsplit("\\", 1)[0] if "\\" in __file__ else __file__.rsplit("/", 1)[0])
import l1model as L

R0, R1 = L.R0, L.R1
WORLD = "--world" in sys.argv   # blits keep their place against the view (V)
TILES = "--tiles" in sys.argv     # fills and aligned blits (TILESET) into a byte tile layer under the objects
TILESET = (sys.argv[sys.argv.index("--tiles") + 1] if TILES else "")
BGFILL = False         # full-width fills as the rows' background, not pieces
OPAQUE = True          # pieces opaque (a palette per piece holding its colours)


class Piece:
    __slots__ = ("kind", "img", "src", "mir", "mode", "x0", "x1", "r0", "r1", "vals", "tag", "pic", "v")

    def px(self, r, x):
        if self.kind == "fill":
            v = self.vals[r - self.r0]
            return (v >> (6 - 2 * (x & 3))) & 3
        return self.img.px(r - self.r0, x - self.x0, self.mir)


def shifted(p, d):
    q = Piece()
    for k in Piece.__slots__:
        setattr(q, k, getattr(p, k, None))
    q.x0, q.x1 = p.x0 + d, p.x1 + d
    return q


def bgpx(bg, r, x):
    return (bg[r - R0] >> (6 - 2 * (x & 3))) & 3


def blit_piece(img, src, kind, mode, col, row, sh):
    col = L.signed(col)
    if kind in ("AR", "MR"):
        col = col - img.w + 1
    p = Piece()
    p.kind, p.img, p.src, p.mir, p.mode = "img", img, src, kind in ("M", "MR"), mode
    p.x0 = 4 * col + (sh >> 1)
    p.x1 = p.x0 + 4 * img.w
    p.r0, p.r1 = row, row + img.rows
    p.tag = (src, kind, row)
    return p


def clipped(p):
    return max(p.x0, 0), min(p.x1, 160), max(p.r0, R0), min(p.r1, R1)


def inside(p, x0, x1, r0, r1):
    a0, a1, b0, b1 = clipped(p)
    if a0 >= a1 or b0 >= b1:
        return True                  # nothing on screen
    return x0 <= a0 and a1 <= x1 and r0 <= b0 and b1 <= r1


def overlaps(p, x0, x1, r0, r1):
    a0, a1, b0, b1 = clipped(p)
    return a0 < x1 and x0 < a1 and b0 < r1 and r0 < b1


class Buf:
    def __init__(self):
        self.bg = bytearray(R1 - R0)
        self.pieces = []
        self.tl = [bytearray(40) for _ in range(R1 - R0)]     # the tile layer (TILES): bytes

    def copy(self):
        b = Buf()
        b.bg = bytearray(self.bg)
        b.pieces = list(self.pieces)
        b.tl = [bytearray(r) for r in self.tl]
        return b

    def render(self):
        if TILES:
            fb = [bytearray(r) for r in self.tl]
        else:
            fb = [bytearray([self.bg[r]] * 40) for r in range(R1 - R0)]
        for p in self.pieces:
            if WORLD and p.kind == "img" and p.v is not None and getattr(self, "view", None) is not None:
                d = (self.view - p.v + 512) % 1024 - 512
                if d:
                    p = shifted(p, d)
            a0, a1, b0, b1 = clipped(p)
            for r in range(b0, b1):
                row = fb[r - R0]
                for x in range(a0, a1):
                    v = p.px(r, x)
                    if p.kind == "img" and p.mode == 0x00:
                        if v == 0:
                            continue
                    elif p.kind == "img" and p.mode >= 0x80:
                        if v == 3:
                            continue
                        v = v & L.px_get(row, x)
                    elif not OPAQUE and v == bgpx(self.bg, r, x):
                        continue
                    L.px_set(row, x, v)
        return fb


def main():
    path = sys.argv[1]
    rules = set((sys.argv[sys.argv.index("--rules") + 1] if "--rules" in sys.argv else "a,b").split(","))
    show = int(sys.argv[sys.argv.index("--show") + 1]) if "--show" in sys.argv else 10
    imgs = {}
    bufs = None
    st = Counter()
    npieces = Counter()
    shown = 0
    for line in open(path):
        p = line.split()
        t = p[0]
        if t == "I":
            imgs[int(p[1], 16)] = L.Img(bytes.fromhex(p[3]))
            continue
        if t == "C" and bufs is None:
            bufs = {"A": Buf(), "B": Buf()}
        if bufs is None:
            continue
        if t == "P":
            n, drawn = int(p[1]), p[2]
            zz = bytes.fromhex(p[3])
            V = 4 * zz[0] + zz[1] // 2
            for bb in bufs.values():
                for q in bb.pieces:
                    if q.pic == n:
                        q.v = V
            bufs[drawn].view = V
            PIC[0] = n + 1
            real = L.parse_dump(p[5] if drawn == "A" else p[7])
            b = bufs[drawn]
            fb = b.render()
            d = sum(1 for r in range(R1 - R0) for x in range(160) if L.px_get(fb[r], x) != L.px_get(real[r], x))
            st["pics"] += 1
            npieces[len(b.pieces) // 10 * 10] += 1
            st["maxpieces"] = max(st["maxpieces"], len(b.pieces))
            if d:
                st["bad"] += 1
                st["badpx"] += d
                BADS.append((n, d))
                if shown < show:
                    shown += 1
                    rows = [r + R0 for r in range(R1 - R0) if fb[r] != real[r]]
                    print("pic %d buf %s: %d pixels differ, rows %s, %d pieces" % (n, drawn, d, rows[:12], len(b.pieces)))
            continue
        if t == "C":
            bufs[p[1]] = Buf()
        elif t == "K":
            bufs[p[1]] = bufs["B" if p[1] == "A" else "A"].copy()
        elif t == "B":
            buf, kind, mode, col, row, sh, src = p[1], p[2], int(p[3], 16), int(p[4]), int(p[5]), int(p[6]), int(p[7], 16)
            q = blit_piece(imgs[src], src, kind, mode, col, row, sh)
            add(bufs[buf], q, rules)
        elif t == "L":
            buf, src, col, row, sh, lim, entry, z52 = p[1], int(p[2], 16), int(p[3]), int(p[4]), int(p[5]), int(p[6]), p[8], int(p[9])
            if src < 0xA000 or (entry == "68" and (z52 >= 0x80 or z52 < 0x14)):
                continue
            r = row
            while True:
                r += 2
                add(bufs[buf], blit_piece(imgs[src], src, "A", 0x01, col, r, sh), rules)
                if r >= lim:
                    break
        elif t == "F":
            do_fill(bufs, p)
    print(dict(st))
    print("pieces a buffer (tens):", sorted(npieces.items()))
    runs = []
    for n, d in BADS:
        if runs and n <= runs[-1][1] + 2:
            runs[-1][1] = n; runs[-1][2] = max(runs[-1][2], d)
        else:
            runs.append([n, n, d])
    print("bad pictures (from-to, most pixels):", [tuple(r) for r in runs])


def do_fill(bufs, p):
    buf, kind = p[1], p[2]
    c0, c1, bot, top, v02, v12, nf = int(p[3]), int(p[4]), int(p[5]), int(p[6]), int(p[8], 16), int(p[9], 16), int(p[10])
    if nf:
        return
    if top >= 0xDD:
        top = 0
    if c0 >= 40:
        if c1 >= 41:
            return
        c0 = 0
    elif c1 >= 41:
        c1 = 40
    n = bot - top
    vals = [v02 if (kind == "rect" or (n - 1 - i) % 2 == 0) else v12 for i in range(n)]
    b = bufs[buf]
    r0, r1 = max(top, R0), min(bot, R1)
    if r0 >= r1:
        return
    if TILES:
        b.pieces = [q for q in b.pieces if not tile_hides(q, 4 * c0, 4 * c1, r0, r1)]
    else:
        b.pieces = [q for q in b.pieces if not inside(q, 4 * c0, 4 * c1, r0, r1)]
    if TILES:
        for r in range(r0, r1):
            for c in range(c0, c1):
                b.tl[r - R0][c] = vals[r - top]
        return
    if c0 == 0 and c1 == 40 and BGFILL:
        for r in range(r0, r1):
            b.bg[r - R0] = vals[r - top]
        return
    q = Piece()
    q.kind, q.img, q.src, q.mir, q.mode = "fill", None, None, False, 0x01
    q.x0, q.x1, q.r0, q.r1 = 4 * c0, 4 * c1, r0, r1
    q.vals = vals[r0 - top:r1 - top]
    q.tag = ("fill",)
    q.pic = PIC[0]
    q.v = None
    if OPAQUE or any(v != b.bg[r - R0] for r, v in zip(range(r0, r1), q.vals)):
        b.pieces.append(q)


BADS = []
PIC = [0]                   # the picture being drawn (its P line's number)


def tile_hides(p, x0, x1, r0, r1):
    """a tile-layer write drops the objects it covers: wholly, or (TILEROWS)
    any object whose rows it covers and whose columns it meets"""
    if inside(p, x0, x1, r0, r1):
        return True
    if "--tilerows" in sys.argv:
        a0, a1, b0, b1 = clipped(p)
        return r0 <= b0 and b1 <= r1 and a0 < x1 and x0 < a1
    return False


def tileable(q):
    if q.mode != 0x01 or q.x0 % 4:
        return False
    if TILESET == "rails":
        return q.src == 0xAA11
    if TILESET == "fixed":
        return q.src in (0xAA11, 0xA9B8, 0xA9E2, 0xAB4A)
    return TILESET == "aligned"


def add(b, q, rules):
    q.pic = PIC[0]
    q.v = None
    a0, a1, b0, b1 = clipped(q)
    if a0 >= a1 or b0 >= b1:
        return
    if TILES and tileable(q):
        b.pieces = [p for p in b.pieces if not tile_hides(p, a0, a1, b0, b1)]
        for r in range(b0, b1):
            for x in range(a0, a1):
                L.px_set(b.tl[r - R0], x, q.px(r, x))
        return
    if q.mode == 0x01 and "a" in rules:
        b.pieces = [p for p in b.pieces if not inside(p, a0, a1, b0, b1)]
    if "b" in rules:
        b.pieces = [p for p in b.pieces if not (p.tag == q.tag and overlaps(p, a0, a1, b0, b1))]
    if "G" in rules:            # a redraw replaces every copy of the image in that row from earlier pictures
        b.pieces = [p for p in b.pieces if not (p.tag == q.tag and p.pic < q.pic)]
    if "g" in rules:            # a redraw replaces the image's copies in that row from earlier pictures
        b.pieces = [p for p in b.pieces if not (p.tag == q.tag and p.pic < q.pic and overlaps(p, a0, a1, b0, b1))]
    b.pieces.append(q)


if __name__ == "__main__":
    main()
