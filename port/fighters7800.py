"""The fighters' parts converted for MARIA objects at the build (FINDINGS "The
fighters as objects: step 2").

Bank 15 places every part of a fighter by its pose's table row + $72 (the
fighters have no vertical position of their own), so each pose's rows are
fixed and its parts can be cut on the band's BAND_ZH-line grid here, ahead of
time (the user's idea: "make the trimmed rows ourselves").

- **Lower bodies** (pose $20, 42 poses): the sprite ($A000/$A02A, row $A07E)
  merged with its mask ($A0A8/$A0D2, row $A126, byte column $A0FC): the
  sprite's colours over the mask's cleared pixels, which become an opaque
  black. Cut into the grid's zones, each slice trimmed to its opaque bytes and
  given its own palette: the game's (skin, grey, white) when the slice has no
  black, else the black palette (skin, black, white: grey made white). Stored
  converted: a blob per pose (the slices' headers and rows), in the art bank.
- **Torsos and the heads' colours** need no conversion: the copy reads the
  game's own images (torsos $A226/$A24C; heads $A1CD/$A1CA, the enemies' by
  type, $AA75).
- **Black-only and merged images,** plain (rows, width, the rows):
  - the heads' black layers: the head mask ($8EC1, head image 0's only) where
    the head's image leaves it uncovered; one for the player's head and one
    for each enemy type's;
  - the pose masks $9A2A and $9A18 (upper poses 6, $14-$1D; 7, $0A-$0D,
    $27), black where the mask clears;
  - the hit stars (not the hawk: FINDINGS "The remaining objects: the
    plan"): each sprite ($942A, $94E6) merged with its mask ($93AB, $9490;
    3 rows higher, the same column), grey made white.

A pose's blob: the sprite's width in bytes, the slice count, then each slice:
  zone | row in zone << 4 | palette << 7   (palette 1: the black palette)
  (rows - 1) << 5 | width                  (width 1-31 bytes)
  byte offset from the sprite's left byte (signed)
  rows x width bytes (160A, the left pixel in bits 7-6)
"""
import collections

import dis as D
import layout7800 as L

TOP = 0x72 - 35               # a table row + $72 is the XEGS line; less 35 the buffer row
BLACK = "K"                   # a mask's cleared pixel: an opaque black
BELT_GAP = 3                  # the belt: a gap of at most this many rows in a column
BELT_ROWS = 6                 # in the sprite's top rows (the jacket's hem: the belt)


def grid_zones():
    """the band's grid zones (first, last buffer row), FB_TOP to BAND_ZEND"""
    band = (L.FB_ROWS - L.FB_TOP + 2) // 3
    out, r = [], L.FB_TOP
    while r <= L.BAND_ZEND:
        c0 = L.FB_TOP + (r - L.FB_TOP) // band * band
        z1 = min(c0 + ((r - c0) // L.BAND_ZH + 1) * L.BAND_ZH, c0 + band) - 1
        out.append((r, z1))
        r = z1 + 1
    return out


ZONES = grid_zones()


def zone_of(row):
    for i, (z0, z1) in enumerate(ZONES):
        if z0 <= row <= z1:
            return i
    raise SystemExit("fighters: buffer row %d is outside the band's grid (rows %d-%d)" % (row, ZONES[0][0], ZONES[-1][1]))


class Art(object):
    """the game's images (scene 1's memory: bank 15's tables and the art are
    the same in every scene)"""

    def __init__(self):
        self.m = D.memory(1)

    def img(self, a):
        m = self.m
        r, w = m[a], m[a + 1]
        return r, w, [[(m[a + 2 + y * w + b] >> (6 - 2 * k)) & 3 for b in range(w) for k in range(4)]
                      for y in range(r)]

    def tab(self, lo, hi, n):
        return [self.m[lo + i] | self.m[hi + i] << 8 for i in range(n)]


def signed(v):
    return v - 256 if v >= 128 else v


def encode_row(vals):
    """pixel values 0-3, 4 a byte, the left pixel in bits 7-6"""
    out = bytearray()
    for b in range(0, len(vals), 4):
        v = 0
        for k in range(4):
            v |= (vals[b + k] if b + k < len(vals) else 0) << (6 - 2 * k)
        out.append(v)
    return bytes(out)


def lower_pixels(art, x, belt=True):
    """pose x's merged lower body: (pixel x from the sprite's left, buffer row) ->
    colour 1-3 or BLACK (belt False: without the belt's black, as the original
    has it)"""
    m = art.m
    s = art.tab(0xA000, 0xA02A, 42)[x]
    mk = art.tab(0xA0A8, 0xA0D2, 42)[x]
    row, mrow, mcol = m[0xA07E + x], m[0xA126 + x], signed(m[0xA0FC + x])
    out = {}
    if mk >> 8:
        mr, mw, mp = art.img(mk)
        if m[0xA2BE + x]:
            # a pose drawn with each image mirrored in its own box ($A2BE:
            # poses 28-32): its mask's column is set for that, so as one
            # merged image (mirrored as a whole) the mask sits at the box's
            # width less its own, less that column
            mcol = art.img(s)[1] - mw - mcol
        for y in range(mr):
            for xx in range(mw * 4):
                if mp[y][xx] == 0:
                    out[(xx + mcol * 4, y + mrow + TOP)] = BLACK
    sr, sw, sp = art.img(s)
    for y in range(sr):
        for xx in range(sw * 4):
            if sp[y][xx]:
                out[(xx, y + row + TOP)] = sp[y][xx]
    # the belt (the user: "the belt area should be black"): the sprite's empty
    # pixels with the figure both above and below in their column, the gap at
    # most BELT_GAP rows, in the sprite's top BELT_ROWS rows, show the
    # background in the original (black in most of the band); as objects they
    # are an opaque black. (Without the row limit, folded legs' short gaps
    # filled too: poses 28, 30)
    for xx in range(sw * 4 if belt else 0):
        ys = [y for y in range(sr) if sp[y][xx]]
        for a, b in zip(ys, ys[1:]):
            if 1 < b - a <= BELT_GAP + 1 and b < BELT_ROWS:
                for y in range(a + 1, b):
                    out.setdefault((xx, y + row + TOP), BLACK)
    return out, sw


def cut(px):
    """the slices of a part: (zone, row in zone, rows, byte offset, width,
    palette, data), each trimmed to its opaque bytes; palette 1 (black) when
    the slice holds black"""
    by = collections.defaultdict(dict)
    for (x, y), v in px.items():
        by[zone_of(y)][(x, y)] = v
    out = []
    for z in sorted(by):
        p = by[z]
        b0 = min(x for x, y in p) // 4
        b1 = max(x for x, y in p) // 4
        r0 = min(y for x, y in p)
        r1 = max(y for x, y in p)
        pal = 1 if any(v == BLACK for v in p.values()) else 0
        conv = {BLACK: 2, 1: 1, 2: 3 if pal else 2, 3: 3}
        data = bytearray()
        for y in range(r0, r1 + 1):
            data += encode_row([conv[p[(x, y)]] if (x, y) in p else 0 for x in range(b0 * 4, b1 * 4 + 4)])
        out.append((z, r0 - ZONES[z][0], r1 - r0 + 1, b0, b1 - b0 + 1, pal, bytes(data)))
    return out


def blob(width, slices):
    out = bytearray([width, len(slices)])
    for z, r0, n, b0, w, pal, data in slices:
        if not (z < 16 and r0 < 8 and 1 <= n <= 8 and 1 <= w <= 31 and -128 <= b0 < 128):
            raise SystemExit("fighters: a slice out of the blob's ranges (zone %d, row %d, %d rows, %d bytes)"
                             % (z, r0, n, w))
        out += bytes([z | r0 << 4 | pal << 7, (n - 1) << 5 | w, b0 & 0xFF]) + data
    return bytes(out)


def unblob(get, a):
    """a blob read back (get: address -> byte): (width, slices)"""
    width, n = get(a), get(a + 1)
    a += 2
    out = []
    for _ in range(n):
        h0, h1, h2 = get(a), get(a + 1), get(a + 2)
        z, r0, pal, rows, w = h0 & 0x0F, (h0 >> 4) & 7, h0 >> 7, (h1 >> 5) + 1, h1 & 0x1F
        a += 3
        data = bytes(get(a + i) for i in range(rows * w))
        a += rows * w
        out.append((z, r0, rows, signed(h2), w, pal, data))
    return width, out


def lower_blobs(art):
    """per pose 0-41, its blob; poses with the same parts share one"""
    blobs, by_key = [], {}
    m = art.m
    for x in range(42):
        key = (art.tab(0xA000, 0xA02A, 42)[x], art.tab(0xA0A8, 0xA0D2, 42)[x], m[0xA07E + x],
               m[0xA126 + x], m[0xA0FC + x])
        if key not in by_key:
            px, w = lower_pixels(art, x)
            by_key[key] = blob(w, cut(px))
        blobs.append(by_key[key])
    return blobs


# ------------------------------------------------ the parts in MARIA's ROM
# FINDINGS "BankSet step 1: the fighters' parts". MARIA reads the parts from
# its own half of the cart; nothing is copied at the flip.
# - **Pre-cut parts** (the lower bodies, the torsos, the pose masks: their
#   rows are fixed by the pose): each slice a window of its whole cell (line
#   g of the cell at page T - g; the lines outside the slice's rows zero), so
#   any zone of the cell reads only its own slice. Both ways: the mirrored
#   ones as rigid mirrors of the box.
# - **Tall images** (the heads, the hit stars: their rows vary): image row r
#   at page P0 - r, with GAP zero rows above and below (shared with the next
#   image in the column: a cell's zone reads at most 7 lines past the image).
# - **The heads in 160B** (FINDINGS "The fighters' heads in MARIA's ROM:
#   160B"): image 0 with its mask's black as one object, colours in palette
#   1 (skin, grey, white), the black as palette 3's colour 1 (TopColours
#   writes $00 there every frame); images 1 and 2 (no mask) stay 160A.
# Records for the CPU (the art bank):
#   a pre-cut part: the box's width (screen bytes), the slice count, then
#     each slice: cell | palette (bit 7 the black one, bit 5 160B), its
#     offset from the box's left (signed), its width (screen bytes), its
#     data's address (low byte) and T;
#   a tall image: the box's width, its rows, palette, address (low), P0.
PAL_GAME, PAL_BLACK, PAL_B = 0x00, 0x80, 0x20
# (V2: the fighters coloured, FINDINGS "The fighters coloured": 160B in the
# upper palette group, P4 skin, black, white; P6 the player's and P7 the
# enemy's grey, belt and trim. The plain parts are the player's, the mirrored
# the enemy's. The object's header palette is 5, the band writer's mark)
PAL_C = 0xA0
C_SKIN, C_GREY, C_WHITE, C_BLACK, C_BELT, C_TRIM = "skin", "grey", "white", "black", "belt", "trim"
TRIM_DIST = 1                 # (the trim: white pixels this near skin that touches the background)


def colour_classes(px, belt_px=(), trim=True):
    """the game's pixels (1 skin, 2 grey, 3 white, BLACK) as colour classes:
    the belt (belt_px: the lower body's belt gaps), the trim (white pixels
    within TRIM_DIST of skin that touches the background: the cuffs, hems and
    collar, not the chest's opening)"""
    out = {}
    skin = [k for k, v in px.items() if v == 1 and any((k[0] + dx, k[1] + dy) not in px
                                                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
    for k, v in px.items():
        if k in belt_px:
            out[k] = C_BELT
        elif v == BLACK:
            out[k] = C_BLACK
        elif v == 1:
            out[k] = C_SKIN
        elif v == 2:
            out[k] = C_GREY
        elif trim and any(abs(k[0] - sx) <= TRIM_DIST and abs(k[1] - sy) <= TRIM_DIST for sx, sy in skin):
            out[k] = C_TRIM
        else:
            out[k] = C_WHITE
    return out


def colour_slices(cl, mir):
    """a coloured part's cells as cell_slices makes them: 160B (PAL_C) where a
    cell holds black, belt or trim, else 160A in the game's palette (PAL_GAME:
    skin, grey, white, which keeps the grey) at half the bytes: [(cell, b0, w,
    palette, window)]"""
    by = collections.defaultdict(dict)
    for k, v in cl.items():
        by[zone_of(k[1])][k] = v
    out = []
    for z in sorted(by):
        p = by[z]
        if any(v in (C_BLACK, C_BELT, C_TRIM) for v in p.values()):
            out += [(zz, b0, w, PAL_C, win) for zz, b0, w, win in cell_slices(colour_160b(p, mir), "B")]
        else:
            g = {C_SKIN: 1, C_GREY: 2, C_WHITE: 3}
            out += [(zz, b0, w, PAL_GAME, win) for zz, b0, w, win in
                    cell_slices({k: g[v] for k, v in p.items()}, "A")]
    return out


def colour_160b(cl, mir):
    """classes as 160B (colour, palette in the group): P4 (0) skin, black,
    white; the player's P6 (2) or, mirrored, the enemy's P7 (3): grey, belt,
    trim"""
    s = 3 if mir else 2
    m = {C_SKIN: (1, 0), C_BLACK: (2, 0), C_WHITE: (3, 0), C_GREY: (1, s), C_BELT: (2, s), C_TRIM: (3, s)}
    return {k: m[v] for k, v in cl.items()}
GAP = 7                       # zero rows a tall image needs above and below
# the enemy types each scene's records showed ($3E, FINDINGS "The enemy's
# mirrored poses": the attract loop, scenes 1-4 and 6, the user's level 3
# recording); a type's head in another scene is the first of these scenes'
HEAD_TYPES = {0: (0, 6), 1: (0, 1, 2, 3, 4, 5), 2: (1, 2, 3, 4, 5), 3: (3, 4, 5), 4: (6,)}
SCENE_OF = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 1, 6: 1}     # (5 unused; 6, the vs fight, level 1's page)


def encode_box(p, x0, wpx, y0, rows, mode):
    """the pixels of p (160A: value 1-3; 160B: (colour 1-3, palette 0-3)) in
    the box (x0, y0, wpx pixels, rows) as 160A or 160B bytes, row by row"""
    out = bytearray()
    for y in range(y0, y0 + rows):
        vals = [p.get((x, y)) for x in range(x0, x0 + wpx)]
        if mode == "A":
            out += encode_row([v or 0 for v in vals])
        else:
            for k in range(0, wpx, 2):
                b = 0
                for j, v in enumerate(vals[k:k + 2]):
                    if v:
                        b |= v[0] << (6 - 2 * j) | v[1] << (2 - 2 * j)
                out.append(b)
    return bytes(out)


def cell_slices(px, mode):
    """px: (x from the box's left in pixels, buffer row) -> value, as
    [(cell, b0 screen bytes, w screen bytes, window: the cell's lines x w
    (160B: 2w) bytes)], each trimmed to its opaque screen bytes"""
    by = collections.defaultdict(dict)
    for (x, y), v in px.items():
        by[zone_of(y)][(x, y)] = v
    out = []
    for z in sorted(by):
        p = by[z]
        z0, z1 = ZONES[z]
        b0 = min(x for x, y in p) // 4
        b1 = max(x for x, y in p) // 4
        out.append((z, b0, b1 - b0 + 1, encode_box(p, b0 * 4, (b1 - b0 + 1) * 4, z0, z1 - z0 + 1, mode)))
    return out


def mirror(px, w):
    """a box w screen bytes wide, mirrored"""
    return {(w * 4 - 1 - x, y): v for (x, y), v in px.items()}


def lower_conv(art, x):
    """pose x's lower body coloured as cut() colours it: (pixel, row) -> 1-3;
    each cell's palette (the black one when the cell holds black: grey made
    white); the box's width"""
    px, sw = lower_pixels(art, x)
    by = collections.defaultdict(dict)
    for k, v in px.items():
        by[zone_of(k[1])][k] = v
    out, pal = {}, {}
    for z, p in by.items():
        blk = any(v == BLACK for v in p.values())
        pal[z] = PAL_BLACK if blk else PAL_GAME
        for k, v in p.items():
            out[k] = {BLACK: 2, 1: 1, 2: 3 if blk else 2, 3: 3}[v]
    return out, pal, sw


def maria_parts(art, mems, colour=False):
    """(precut, tall, head_var): precut: name -> (width, [(cell, b0, w,
    palette, window)]); tall: name -> (width, rows, palette, row bytes);
    head_var: (scene 0-6, head index 0-23: the player's 0-2, type t's 3 + 3t
    + 0-2) -> its tall image's name (+ "/m" the mirrored one). mems: scene ->
    memory (some types' heads are in scene data)"""
    m = art.m
    precut, tall = {}, {}
    for x in range(42):
        if colour:          # (V2: 160B, the grey back, the belt, the trim)
            gp, sw = lower_pixels(art, x)
            nob, _ = lower_pixels(art, x, belt=False)
            cl = colour_classes(gp, set(gp) - set(nob))
            for mir in (0, 1):
                # (whose: the enemy's mirrored, but poses 28-32 ($A2BE) the
                # other way round, as the game draws them)
                precut["low%d%s" % (x, "/m" * mir)] = (sw, colour_slices(mirror(cl, sw) if mir else cl,
                                                                         mir ^ bool(m[0xA2BE + x])))
            continue
        px, pal, sw = lower_conv(art, x)
        for mir in (0, 1):
            q = mirror(px, sw) if mir else px
            precut["low%d%s" % (x, "/m" * mir)] = (sw, [(z, b0, w, pal[z], win)
                                                        for z, b0, w, win in cell_slices(q, "A")])
    for y in range(38):
        r, w, p = art.img(m[0xA226 + y] | m[0xA24C + y] << 8)
        row0 = m[0xA298 + y] + TOP
        px = {(xx, row0 + yy): v for yy in range(r) for xx, v in enumerate(p[yy]) if v}
        if colour:          # (V2: 160B, the trim)
            cl = colour_classes(px)
            for mir in (0, 1):
                precut["torso%d%s" % (y, "/m" * mir)] = (w, colour_slices(mirror(cl, w) if mir else cl, mir))
            continue
        for mir in (0, 1):
            q = mirror(px, w) if mir else px
            precut["torso%d%s" % (y, "/m" * mir)] = (w, [(z, b0, ww, PAL_GAME, win)
                                                         for z, b0, ww, win in cell_slices(q, "A")])
    for a, row0 in ((0x9A2A, 0x0F + TOP), (0x9A18, 0x16 + TOP)):
        r, w, p = art.img(a)
        px = {(xx, row0 + yy): 2 for yy in range(r) for xx, v in enumerate(p[yy]) if v == 0}
        for mir in (0, 1):
            q = mirror(px, w) if mir else px
            precut["pmask_%04X%s" % (a, "/m" * mir)] = (w, [(z, b0, ww, PAL_BLACK, win)
                                                            for z, b0, ww, win in cell_slices(q, "A")])
    # the heads: the player's own three, each type's three by scene
    hsrc = [(0xA1CD, 0xA1CA)] + [(lo, lo - 3) for lo in (0xA1D3, 0xA2EB, 0xA2F1, 0xA2F7, 0xA2FD, 0xAAF6, 0xAAFC)]
    haddr = [m[lo + i] | m[hi + i] << 8 for lo, hi in hsrc for i in range(3)]
    mr, mw, mp = art.img(0x8EC1)
    seen, head_var, first_scene = {}, {}, {}
    for s in sorted(HEAD_TYPES):
        for t in HEAD_TYPES[s]:
            first_scene.setdefault(t, s)
    for sc in range(7):
        for idx in range(24):
            s = SCENE_OF[sc]
            if idx >= 3:
                t = (idx - 3) // 3
                if t not in first_scene:
                    continue
                if t not in HEAD_TYPES[s]:
                    s = first_scene[t]
            a, img = haddr[idx], idx % 3
            mm = mems[s] if a < 0x8000 else m
            hr, hw = mm[a], mm[a + 1]
            hp = [[(mm[a + 2 + y * hw + b] >> (6 - 2 * k)) & 3 for b in range(hw) for k in range(4)]
                  for y in range(hr)]
            px = {}
            if img == 0:
                # the mask's black where the head leaves it uncovered: at the
                # head's place for the player's own, else a byte right and 2
                # rows down of the head (in the image's unmirrored frame:
                # $A9AE: $06 - 2, $05 - $2C)
                dx, dy = (0, 0) if idx < 3 else (4, 2)
                for yy in range(mr):
                    for xx in range(mw * 4):
                        if mp[yy][xx] == 0:
                            px[(xx + dx, yy + dy)] = (1, 3)
            for yy in range(hr):
                for xx in range(hw * 4):
                    if hp[yy][xx]:
                        px[(xx, yy)] = (hp[yy][xx], 1)
            if not px:
                continue
            key = (img == 0, tuple(sorted(px.items())))
            if key not in seen:
                name = "head%d" % len(seen)
                seen[key] = name
                w = max(x for x, y in px) // 4 + 1
                rows = max(y for x, y in px) + 1
                for mir in (0, 1):
                    q = mirror(px, w) if mir else px
                    if img == 0:
                        tall[name + "/m" * mir] = (w, rows, PAL_B, encode_box(q, 0, w * 4, 0, rows, "B"))
                    else:
                        tall[name + "/m" * mir] = (w, rows, PAL_GAME, encode_box(
                            {k: v[0] for k, v in q.items()}, 0, w * 4, 0, rows, "A"))
            head_var[(sc, idx)] = seen[key]
    # the hit stars: each sprite merged with its mask (3 rows above it), grey
    # made white, in the black palette
    for spr, msk in ((0x942A, 0x93AB), (0x94E6, 0x9490)):
        sr, sw, sp = art.img(spr)
        r, kw, kp = art.img(msk)
        px = {}
        for yy in range(r):
            for xx in range(kw * 4):
                if kp[yy][xx] == 0:
                    px[(xx, yy)] = 2
        for yy in range(sr):
            for xx in range(sw * 4):
                if sp[yy][xx]:
                    px[(xx, yy + 3)] = 3 if sp[yy][xx] == 2 else sp[yy][xx]
        w, rows = max(kw, sw), max(sr + 3, r)
        tall["star_%04X" % spr] = (w, rows, PAL_BLACK, encode_box(px, 0, w * 4, 0, rows, "A"))
    return precut, tall, head_var


class MariaSpace(object):
    """MARIA's ROM pages as the packer sees them (256 columns each): data,
    and rows kept zero for the tall images' gaps. ranges: the pages, (first,
    last) each, consecutive within a range only: $80-$FF (the window block
    and the fixed bank); V2: $40-$7F and $C0-$FF (MARIA's two fixed banks,
    FINDINGS "The ROM by scene: the plan"), no window across the gap"""

    def __init__(self, data, ranges=((0x80, 0xFF),)):
        self.ranges = tuple(ranges)
        self.pages = [p for lo, hi in self.ranges for p in range(lo, hi + 1)]
        self.ix = {p: i for i, p in enumerate(self.pages)}
        self.data = data                          # bytearray, the pages in order
        self.occ = [0] * len(self.pages)          # bit c: column c holds data
        self.zero = [0] * len(self.pages)         # bit c: kept zero

    def take(self, page, c0, w):
        self.occ[self.ix[page]] |= ((1 << w) - 1) << c0

    def get(self, a):
        """the byte at MARIA address a"""
        return self.data[self.ix[a >> 8] * 256 + (a & 0xFF)]

    def _within(self, lo, hi):
        return any(rlo <= lo and hi <= rhi for rlo, rhi in self.ranges)

    @staticmethod
    def _fit(mask, w):
        free = ~mask & ((1 << 256) - 1)
        run = free
        for i in range(1, w):
            run &= free >> i
        if not run:
            return None
        return (run & -run).bit_length() - 1

    def window(self, w, rows, data):
        """a window (rows x w bytes, line g at page T - g): (low byte, T)"""
        for t in reversed(self.pages):
            if not self._within(t - rows + 1, t):
                continue
            mask = 0
            for p in range(t - rows + 1, t + 1):
                mask |= self.occ[self.ix[p]] | self.zero[self.ix[p]]
            c = self._fit(mask, w)
            if c is not None:
                for g in range(rows):
                    a = self.ix[t - g] * 256 + c
                    self.data[a:a + w] = data[g * w:(g + 1) * w]
                    self.take(t - g, c, w)
                return c, t
        raise SystemExit("fighters: no room in MARIA's ROM for a %d x %d window" % (w, rows))

    def tall(self, w, rows, data):
        """a tall image (row r at page P0 - r, GAP zero rows above and below):
        (low byte, P0)"""
        for p0 in reversed(self.pages):
            if not self._within(p0 - rows - GAP + 1, p0 + GAP):
                continue
            gaps = list(range(p0 + 1, p0 + GAP + 1)) + list(range(p0 - rows - GAP + 1, p0 - rows + 1))
            mask = 0
            for p in range(p0 - rows + 1, p0 + 1):
                mask |= self.occ[self.ix[p]] | self.zero[self.ix[p]]
            for p in gaps:
                mask |= self.occ[self.ix[p]]
            c = self._fit(mask, w)
            if c is not None:
                for r in range(rows):
                    a = self.ix[p0 - r] * 256 + c
                    self.data[a:a + w] = data[r * w:(r + 1) * w]
                    self.take(p0 - r, c, w)
                for p in gaps:
                    self.zero[self.ix[p]] |= ((1 << w) - 1) << c
                return c, p0
        raise SystemExit("fighters: no room in MARIA's ROM for a %d x %d tall image" % (w, rows))

    def free_bytes(self):
        return sum(256 - bin(o | z).count("1") for o, z in zip(self.occ, self.zero))


def pack(space, precut, tall):
    """every tall image and window into MARIA's ROM (identical ones once): the
    records, name -> bytes"""
    rec, at = {}, {}
    for name in sorted(tall, key=lambda n: (-len(tall[n][3]) // tall[n][1], -tall[n][1], n)):
        w, rows, pal, data = tall[name]
        if data not in at:
            at[data] = space.tall(len(data) // rows, rows, data)
        lo, p0 = at[data]
        rec[name] = bytes([w, rows, pal, lo, p0])
    wins = sorted({(ZONES[z][1] - ZONES[z][0] + 1, win) for n, (W, sl) in precut.items()
                   for z, b0, w, pal, win in sl}, key=lambda k: (-k[0], -len(k[1]), k[1]))
    for rows, win in wins:
        at[win] = space.window(len(win) // rows, rows, win)
    for name, (W, sl) in precut.items():
        r = bytearray([W, len(sl)])
        for z, b0, w, pal, win in sl:
            lo, t = at[win]
            r += bytes([z | pal, b0 & 0xFF, w, lo, t])
        rec[name] = bytes(r)
    return rec


def check_maria(get, rec, precut, tall):
    """each record read back through MARIA's view (get: address -> byte)
    against its source: windows, tall images and their gaps"""
    for name, (W, sl) in precut.items():
        r = rec[name]
        if r[0] != W or r[1] != len(sl):
            raise SystemExit("fighters: %s's record is wrong" % name)
        for k, (z, b0, w, pal, win) in enumerate(sl):
            cz, ob, ow, lo, t = r[2 + 5 * k:7 + 5 * k]
            rows = ZONES[z][1] - ZONES[z][0] + 1
            dw = len(win) // rows
            got = bytes(get((t - g) * 256 + lo + i) for g in range(rows) for i in range(dw))
            if (cz & 0x0F, cz & 0xE0, signed(ob), ow) != (z, pal, b0, w) or got != win:
                raise SystemExit("fighters: %s's slice %d reads back wrong" % (name, k))
    for name, (w, rows, pal, data) in tall.items():
        rw, rr, rp, lo, p0 = rec[name]
        dw = len(data) // rows
        got = bytes(get((p0 - r) * 256 + lo + i) for r in range(rows) for i in range(dw))
        gaps = [get((p0 - r) * 256 + lo + i) for r in list(range(-GAP, 0)) + list(range(rows, rows + GAP))
                for i in range(dw)]
        if (rw, rr, rp) != (w, rows, pal) or got != data or any(gaps):
            raise SystemExit("fighters: %s reads back wrong" % name)


if __name__ == "__main__":
    art = Art()
    lb = lower_blobs(art)
    uniq = {id(b): b for b in lb}
    print("fighters: %d lower-body blobs (%d slices) %d bytes" % (
        len(uniq), sum(b[1] for b in uniq.values()), sum(len(b) for b in uniq.values())))
    print("zones:", " ".join("%d-%d" % z for z in ZONES))
