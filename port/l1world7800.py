"""Level 1's background as worlds of tiles (FINDINGS "Level 1: the cliffs
broken; the background as a world of tiles"): each world (structure 0,
structure 1, the cutscene's room) drawn from port/l1world.txt (its draws
at world x, from probes/l1worldlist.py) with the scene's own images, then cut
into two-byte characters (8 pixels) per zone: a map per zone row and the
characters, MARIA's character mode, the scroll in the headers alone.

World x = screen x + V... as the list says: a draw at world x shows at screen
x = world x + V (V = 4 x $52 + $50 / 2)."""
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import worldcfg as WC           # noqa: E402
R0, R1 = 65, 146
BASE = {"0": ((65, 69, 0xAA), (77, 118, 0x00), (118, 146, 0x55)),
        "0b": ((65, 69, 0xAA), (77, 118, 0x00), (118, 146, 0x55)),
        "1": ((65, 69, 0xAA), (77, 118, 0x00), (118, 146, 0x55)),
        "c": ()}
RAILS = {"0": (0xAA11, 1, 69), "0b": (0xAA11, 1, 69), "1": (0xAA11, 1, 69)}   # (the rails: image, bank, row; under all)
WORLDS = ("0", "0b", "1", "c")
WORLDS2 = ("2", "2c", "2p")
RANGES = {}                     # (each world's screen range: load's R lines)


def load(path=os.path.join(HERE, "l1world.txt"), drop=()):
    """{world: [draw]}: ("B", src, bank, kind, mode, row, x), ("L", src, bank,
    kind, row, lim, x), ("F", kind, top, bot, v02, v12, x0, x1); path one
    world list or several. drop: level 1's images left out of its worlds
    (l1world.txt's only: the ones in front of the fighters, objects)"""
    out = defaultdict(list)
    paths = [path] if isinstance(path, str) else list(path)
    for l in (l for p in paths for l in open(p)
              if not (os.path.basename(p) == "l1world.txt" and l.split()[:1] in (["B"], ["L"])
                      and int(l.split()[2], 16) in drop)):
        p = l.split()
        if not p or p[0].startswith("#"):
            continue
        if p[0] == "R":
            RANGES[p[1]] = (int(p[2]), int(p[3]))
        elif p[0] == "B":
            out[p[1]].append(("B", int(p[2], 16), int(p[3]), p[4], int(p[5], 16), int(p[6]), int(p[7])))
        elif p[0] == "L":
            out[p[1]].append(("L", int(p[2], 16), int(p[3]), p[4], int(p[5]), int(p[6]), int(p[7])))
        elif p[0] == "F":
            out[p[1]].append(("F", p[2], int(p[3]), int(p[4]), int(p[5], 16), int(p[6], 16), int(p[7]), int(p[8])))
    return out


class Canvas(object):
    """a world's pixels (2-bit) for rows R0-R1, world x from x0 to x1"""

    def __init__(self, world, x0, x1):
        self.world, self.x0, self.x1 = world, x0, x1
        self.px = {}
        for r in range(R0, R1):
            v = next((b for a, e, b in BASE[world] if a <= r < e), 0)
            row = [(v >> (6 - 2 * (k & 3))) & 3 for k in range(x1 - x0)]
            self.px[r] = row

    def get(self, r, x):
        return self.px[r][x - self.x0]

    def put(self, r, x, v):
        if R0 <= r < R1 and self.x0 <= x < self.x1:
            self.px[r][x - self.x0] = v


def image(get, bank, src):
    rows, w = get(bank, src), get(bank, src + 1)
    return rows, w, [get(bank, src + 2 + i) for i in range(rows * w)]


def blit(cv, img, kind, mode, row, x):
    rows, w, d = img
    mir = kind in ("M", "MR")
    for r in range(rows):
        y = row + r
        if not (R0 <= y < R1):
            continue
        for k in range(4 * w):
            kk = 4 * w - 1 - k if mir else k
            v = (d[r * w + (kk >> 2)] >> (6 - 2 * (kk & 3))) & 3
            xx = x + k
            if not (cv.x0 <= xx < cv.x1):
                continue
            if mode == 0x00:
                v |= cv.get(y, xx)
            elif mode >= 0x80:
                v &= cv.get(y, xx)
            cv.put(y, xx, v)


def fill(cv, kind, top, bot, v02, v12, x0, x1):
    for y in range(top, bot):
        v = v02 if (kind == "rect" or (bot - 1 - y) % 2 == 0) else v12
        for xx in range(x0, x1):
            cv.put(y, xx, (v >> (6 - 2 * (xx & 3))) & 3)


def extent(draws, get):
    """a world's x range, 8-pixel aligned"""
    lo, hi = 10 ** 6, -10 ** 6
    for d in draws:
        if d[0] in ("B", "L"):
            rows, w = get(d[2], d[1]), get(d[2], d[1] + 1)
            lo, hi = min(lo, d[-1]), max(hi, d[-1] + 4 * w)
        else:
            lo, hi = min(lo, d[6]), max(hi, d[7])
    return lo - (lo % 8), hi + (-hi % 8)


def render(world, draws, get, x0=None, x1=None):
    if x0 is None:
        x0, x1 = extent(draws, get)
    cv = Canvas(world, x0, x1)
    imgs = {}
    if world in RAILS:              # (the rails' rows: its image across the world)
        src, bank, row = RAILS[world]
        img = image(get, bank, src)
        for x in range(x0 - x0 % (4 * img[1]), x1, 4 * img[1]):
            blit(cv, img, "A", 0x01, row, x)
    for d in draws:
        if d[0] == "B":
            img = imgs.setdefault((d[2], d[1]), image(get, d[2], d[1]))
            blit(cv, img, d[3], d[4], d[5], d[6])
        elif d[0] == "L":
            img = imgs.setdefault((d[2], d[1]), image(get, d[2], d[1]))
            r = d[4]
            while True:                 # (the column routine: a piece every 2 rows
                r += 2                  # from its row + 2, the last at or past its limit)
                blit(cv, img, d[3], 0x01, r, d[6])
                if r >= d[5]:
                    break
        else:
            fill(cv, *d[1:])
    return cv


def world_range(world):
    """the world x range the screen can show (8-pixel aligned; with the fine
    scroll's extra character)"""
    a, b = RANGES[world]
    return a - (a % 8), b + 8 + (-b % 8)


def cut(cv, zones):
    """the canvas cut into 8-pixel tiles per zone: {zone: [tile]}, a tile the
    zone's lines' two bytes each ((b0, b1) per line, line 0 first)"""
    out = {}
    for zi, (z0, h) in enumerate(zones):
        row = []
        for x in range(cv.x0, cv.x1, 8):
            t = []
            for r in range(z0, z0 + h):
                bs = []
                for half in (0, 4):
                    b = 0
                    for q in range(4):
                        v = cv.get(r, x + half + q) if R0 <= r < R1 else 0
                        b |= v << (6 - 2 * q)
                    bs.append(b)
                t.append(tuple(bs))
            row.append(tuple(t))
        out[zi] = row
    return out


# ------------------------------------------------------------- the tiles
CH_LINES = 10                   # (the tallest zone: a character's line pages, CHBASE on)
VIEW_COLS = 21                  # (the characters a zone's header reads: 168 pixels)
CUT_MIN = 16                    # (a map row's run cut if that saves this much)
WORLD_IDS = {"0": 0, "0b": 1, "1": 2, "c": 3}    # (the 6502's L1_WLD: the world's number)
FIXED = {"c"}                   # (the rooms: their tiles fixed on the screen, not scrolled)
# levels 2-4's (port/worldcfg.py: their bases, rooms, numbers from 4 on in
# its order; the attract loop's, scene 0's, last: 12 on)
for _sc in sorted(WC.CFG, key=lambda s: (s == 0, s)):
    _c = WC.CFG[_sc]
    for _w in _c["scrolled"] + _c["rooms"]:
        BASE[_w] = tuple(_c["base"].get(_w, ()))
        WORLD_IDS[_w] = len(WORLD_IDS)
    FIXED |= set(_c["rooms"])
STRUCT = {"0", "0b", "1"}       # (level 1's: the world follows the game's structure, L1Mark)


class Tiles(object):
    """the worlds as two-byte characters: the character set (indices
    tallest first, a shorter tile sharing a taller one whose lines from the
    bottom up begin the same: zones of any height read the same line pages,
    line g of an h-line zone at CHBASE + h - 1 - g), each world's map rows
    (one per zone: its characters' map bytes, 2 x index), each world's
    origin (K: the world x at map column 0, negated). A map byte is base +
    2 x index (the set's line pages from byte base)"""

    def __init__(self, get, zones, path=os.path.join(HERE, "l1world.txt"), worlds=WORLDS, base=0, drop=()):
        lists = load(path, drop)
        self.zones, self.worlds = zones, worlds
        self.rows, self.k, cut_all = {}, {}, {}
        for w in worlds:
            x0, x1 = world_range(w)
            cv = render(w, lists[w], get, x0, x1)
            cut_all[w] = cut(cv, zones)
            self.k[w] = -x0
        seqs = sorted({tuple(reversed(t)) for w in worlds for row in cut_all[w].values() for t in row},
                      key=lambda q: (-len(q), q))
        self.idx = []                      # each index: its bytes from the bottom line up
        where = {}
        for q in seqs:
            hit = next((i for i, r in enumerate(self.idx) if len(r) >= len(q) and r[:len(q)] == q), None)
            if hit is None:
                hit = len(self.idx)
                self.idx.append(q)
            where[q] = hit
        self.base = base
        if base + 2 * len(self.idx) > 256:
            raise SystemExit("the tiles (%s %s): %d characters from byte %d, past the page"
                             % (path, worlds, len(self.idx), base))
        for w in worlds:
            for zi, row in cut_all[w].items():
                self.rows[(w, zi)] = bytes(base + 2 * where[tuple(reversed(t))] for t in row)

    def blank(self):
        """the map byte of the blank character (all lines 0)"""
        return self.base + 2 * next(i for i, q in enumerate(self.idx) if not any(b for pair in q for b in pair))

    def short(self, row):
        """a map row as stored (FINDINGS "Level 2 as tiles"): its longest run
        of one character cut to the view's 21 (VIEW_COLS), if that saves
        CUT_MIN bytes or more; and the cut's place L (the run's first column)
        and length D. L1Tiles maps the view's first column c0: before L as
        it is, in L to L + D - 1 to L (the run's), past them c0 - D"""
        best, i = (0, 0), 0
        while i < len(row):
            j = i
            while j < len(row) and row[j] == row[i]:
                j += 1
            if j - i > best[1] - best[0]:
                best = (i, j)
            i = j
        d = best[1] - best[0] - VIEW_COLS
        if d < CUT_MIN:
            return row, 0, 0
        return row[:best[0] + VIEW_COLS] + row[best[1]:], best[0], d

    def extent(self, row):
        """a map row's first and last columns not blank (255, 0: none)"""
        cols = [i for i, b in enumerate(row) if b != self.blank()]
        return (cols[0], cols[-1]) if cols else (255, 0)

    def pages(self):
        """the character set's line pages: [bytes of page CHBASE + o from
        byte base], each its indices' two bytes from index 0 (tallest first:
        a prefix)"""
        out = []
        for o in range(CH_LINES):
            n = sum(1 for q in self.idx if len(q) > o)
            if not n:
                out.append(b"")
                continue
            assert all(len(q) > o for q in self.idx[:n])
            out.append(bytes(b for q in self.idx[:n] for b in q[o]))
        return out


def stream(chunks):
    """the loader's byte stream for [(address, bytes)]: 0, address lo, hi to
    move on; n (1-127) and n bytes: as they are; $80 + n and a byte: it n
    times; 0, 0, 0 the end"""
    out = bytearray()
    for at, data in chunks:
        out += bytes([0, at & 0xFF, at >> 8])
        i = 0
        while i < len(data):
            j = i
            while j < len(data) and data[j] == data[i] and j - i < 127:
                j += 1
            if j - i >= 3:
                out += bytes([0x80 + j - i, data[i]])
                i = j
                continue
            k = i
            while k < len(data) and k - i < 127:
                if k + 2 < len(data) and data[k] == data[k + 1] == data[k + 2]:
                    break
                k += 1
            out += bytes([k - i]) + data[i:k]
            i = k
    return bytes(out) + bytes(3)
