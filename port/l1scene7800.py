"""Level 1 without the blitter: the build's part (FINDINGS "Level 1 without
the blitter: the data and the plan").

Level 1's scenery below the top rows (buffer rows FB_TOP-145) is no longer
drawn into the bitmap: each thing the game draws there (a blit, a column of
the column routine, a fill) is an instance, shown as one object for each
zone it crosses, reading a window (the zone's lines x the shape's bytes,
line g at page T - g) the loader renders into cart RAM from the scene
page's own images. This module makes the zones, the shapes (from the
inventory port/l1shapes.txt), their windows and where they go."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import layout7800 as L        # noqa: E402
import worldcfg as WC           # noqa: E402

# the rows' backgrounds, and how a window's pixels are made for them: the
# colour of the background transparent (0), black where that colour's index
# was, the zone object's palette holding black there (TopColours)
SKY, BLACK, FLOOR = 2, 0, 1
SKY_END, FLOOR_TOP = 69, 118          # rows FB_TOP-68 over the sky, 118 on over the floor
PAL_OF = {SKY: 2, BLACK: 1, FLOOR: 3}  # (palette 2: TOP_PAL1, black at 2; 3: TOP_PAL2, black at 1)
PAL_MASK = 3                           # an AND mask's black (index 1)


FENCE_END = 77                         # the fence's rows (69-76): the rails between
                                       # (sky, black and white) under the pieces


def row_bg_l1(r):
    """(level 1) the conversion a row's pieces get: over the sky, colour 2
    clear; over black, as drawn; over the floor, and over the fence's rows
    (the rails under them, their colours black, sky and white: palette 3's),
    colour 1 clear and black opaque"""
    if r < SKY_END:
        return SKY
    if r < FENCE_END:
        return FLOOR
    return BLACK if r < FLOOR_TOP else FLOOR


CUR = None                      # (the set in use: use(); level 1's till then)


def row_bg(r):
    """the conversion a row's pieces get, in the set in use"""
    return CUR.rowbg(r) if CUR else row_bg_l1(r)


def buffer_zones(d):
    """the zones BuildDll makes of a run list's buffer rows (band on: the title
    off), FB_TOP to FB_ROWS-1: [(first row, lines)] (as build7800.zones counts
    them; a flagged last row is a zone of its own)"""
    out = []
    for i in range(0, len(d) - 1, 3):
        k, n, arg = d[i], d[i + 1], d[i + 2]
        if k & 0x3F != 2:
            continue
        flag = 1 if k & 0x80 else 0
        n -= flag
        r = arg
        band = (L.FB_ROWS - L.FB_TOP + 2) // 3
        while n:
            if r >= L.FB_ROWS or r < L.FB_TOP:
                h = min(16, n) if r >= L.FB_ROWS else min(16, n, L.TOP_ZONE - r % L.TOP_ZONE, L.FB_TOP - r)
                r += h
                n -= h
                continue
            zh = L.BAND_ZH - (r - L.FB_TOP) % band % L.BAND_ZH if r <= L.BAND_ZEND else 16
            h = min(zh, n, band - (r - L.FB_TOP) % band, L.FB_ROWS - r)
            out.append((r, h))
            r += h
            n -= h
        if flag and L.FB_TOP <= r < L.FB_ROWS:
            out.append((r, 1))
    return out


# level 1's zones over buffer rows FB_TOP-145 (its play lists $1908/$19B3,
# scenes 1 and 6: the build checks)
ZONES = [(65, 8), (73, 5), (78, 3), (81, 8), (89, 3), (92, 8), (100, 8), (108, 8), (116, 3), (119, 8),
         (127, 8), (135, 10), (145, 1)]
ZBOT = 11                       # the bottom zones (rows 135 on: not the band's)
assert ZONES[ZBOT][0] == 135 and len(ZONES) == ZBOT + 2
assert len(ZONES) == 13          # (L1Tiles0: world x 13 + zone)
LISTS = (0x1908, 0x19B3)
# cart RAM for the windows: the bitmap's pages, past their heads; then pages
# $40-$4D, unused in level 1 (measured: FINDINGS "Level 1 without the
# blitter: steps 3 and 4"), bytes 16-239. A window's lines are consecutive
# pages of one block
WIN_BLOCKS = [(range(0x58, 0x73), 16, 256), (range(0x40, 0x4E), 16, 240)]
assert all(0x40 <= p < 0x80 for pages, lo, hi in WIN_BLOCKS for p in pages)   # (an entry's page: 6 bits)
# (V2: no cart RAM; a set's windows, characters and cells in its scene's
# own MARIA window, $8000-$BFFF, all of it: the 64 pages from WIN_BASE an
# entry's 6 bits name; PRE_USED: page -> 256 flags, bytes taken before,
# the text's in banks 0 and 4. FINDINGS "The ROM by scene: the MARIA side")
WIN_BASE = 0x80 if L.V2 else 0x40
V2_BLOCKS = [(range(0x80, 0xC0), 0, 256)]
PRE_USED = {}
WIN_PAGES = range(0x58, 0x73)
WIN_LO = 16
KIND_STORE, KIND_AND, KIND_OR, KIND_OVER = 0, 1, 2, 3
# an overlay's colour and its value by its palette (the base shape's parts
# with all four colours: the base shows its least-used one clear, the
# overlay draws just that colour; its entries follow the base's in the
# base's record, flags bit 2)
OVER_OF_PAL = {1: (1, 1), 2: (0, 2), 3: (2, 2)}           # palette: (colour, value)
PAL_OF_OVER = {c: p for p, (c, v) in OVER_OF_PAL.items()}


class Shape(object):
    """a line of the inventory: B (a blit) or L (a column); or the rails (R:
    the image's columns repeated to RAILS_W bytes, from x 0 and RAILS_W * 4)"""
    tile = False
    front = False               # (in front of the fighters: after them in a zone's list)
    over = False                # (followed by its overlay)
    sky = False                 # (the rails with the sky above them: SKYRAILS)

    def __init__(self, line):
        p = line.split()
        if p[0] == "S":           # a solid strip: value, first row, past the last
            self.kind, self.src, self.bank, self.mir, self.row = "S", int(p[1], 16), 1, 0, int(p[2])
            self.mode, self.lim, self.tile = KIND_OR, int(p[3]), False
            return
        if p[0] == "R":           # (as drawn: under the pieces, palette 1)
            self.kind, self.src, self.bank, self.mir, self.row = "B", int(p[1], 16), int(p[2]), 0, int(p[3])
            self.mode, self.lim, self.tile = KIND_OR, None, True
            return
        self.kind = p[0]
        self.src, self.bank = int(p[1], 16), int(p[2])
        self.mir, self.row = int(p[3]), int(p[4])
        if self.kind == "B":
            m = int(p[5])
            self.mode = KIND_STORE if 0 < m < 0x80 else (KIND_AND if m >= 0x80 else KIND_OR)
            self.lim = None
        else:                     # (a column: its limit, then its mode if not a store)
            self.mode, self.lim = KIND_STORE, int(p[5])
            if len(p) > 6:
                m = int(p[6])
                self.mode = KIND_STORE if 0 < m < 0x80 else (KIND_AND if m >= 0x80 else KIND_OR)

    def tops(self):
        """the rows its pieces start on (a column: every 2 rows to the first
        at or past the limit)"""
        if self.kind == "B":
            return [self.row]
        out, r = [self.row], self.row
        while True:
            r += 2
            out.append(r)
            if r >= self.lim:
                return out


RAILS = 0xAA11          # the fence's rails: one shape, 20 bytes wide, twice
RAILS_ROW, RAILS_W = 69, 20


def with_overlays(get, shapes):
    """each stored shape with a four-colour part followed by its overlay
    (a copy, mode KIND_OVER), the base marked (over)"""
    out = []
    for sh in shapes:
        out.append(sh)
        if sh.mode == KIND_STORE and sh.kind != "S" and not sh.tile and four_colour_parts(get, sh):
            ov = Shape.__new__(Shape)
            ov.__dict__.update(sh.__dict__)
            ov.mode = KIND_OVER
            sh.over = True
            out.append(ov)
    return out


def four_colour_parts(get, sh):
    px, w = pixels(get, sh)
    return [p for p, (zi, z0, h, a, e, bg) in enumerate(PARTS)
            if bg != WHOLE and len({v for r in range(a, e) if r in px for v in px[r]}) == 4]


def skyrails():
    """the rails with the sky's rows above them (its limit to its row: $AA),
    one strip for both (zone 0 holds the sky's rows and the rails' first:
    two strips there cost MARIA the time its last objects need: FINDINGS
    "Level 1 without the blitter: MARIA's time")"""
    sh = Shape("R %04X %d %d" % (RAILS, 1, RAILS_ROW))
    sh.sky, sh.lim = True, FB_TOP_
    return sh


# (V2) level 1's images the game draws after the fighters (FINDINGS "The
# torii in front"): the white torii's front post ($A684, a column), the
# gate structure's front post ($A000, a column) and its foot ($A2DE):
# out of its worlds, shapes in front (probes/tmp-l1front.lua)
L1_FRONT = {0xA684, 0xA000, 0xA2DE} if L.V2 else set()
# (and they stay in its worlds' tiles: the front copy is drawn only while
# a fighter's box meets its columns, L1FrHit; FINDINGS "The torii in
# front". None left out of the worlds)
L1_DROP = set()


def world_images(path=os.path.join(HERE, "l1world.txt")):
    """the images the worlds draw (their tiles: not objects)"""
    return {int(l.split()[2], 16) for l in open(path) if l.split() and l.split()[0] in ("B", "L")} - L1_FRONT


NOT_LEVEL1 = range(0xB300, 0xBB00)     # (level 2's first picture's, in the clean run's log)


def inventory(path=os.path.join(HERE, "l1shapes.txt")):
    """level 1's objects: the inventory's shapes but the worlds' images
    (FINDINGS "Level 1: the cliffs broken; the background as a world of
    tiles"): the posts, the mountain's base, the player's climb, Akuma"""
    tiles = world_images()
    # (a column's line here: its fields, then the times seen, not a mode as
    # in worldcfg's front_cols: FINDINGS "The torii in front")
    # (a line "V2 ...": V2's only; v1's bank 6 has no room: the cliff fall's
    # shapes, FINDINGS "Recording 02")
    lines = [l[3:] if l.startswith("V2 ") else l for l in open(path)
             if l.strip() and not l.startswith("#") and (L.V2 or not l.startswith("V2 "))]
    out = [Shape(" ".join(l.split()[:6]) if l.split()[0] == "L" else l) for l in lines]
    out = [sh for sh in out if sh.src not in tiles and sh.src not in NOT_LEVEL1]
    for sh in out:
        sh.front = sh.src in L1_FRONT
    # (in their image addresses' low bytes' order: the capture looks a draw
    # up from the first with its low byte, first_of_lo)
    return sorted(out, key=lambda sh: sh.src & 0xFF)


def room_inventory(name):
    """a room scene's objects (FINDINGS "Levels 2-4 without the blitter"):
    its inventory's OR and AND blits (probes/objinventory.py: the stores and
    the fills are drawn into the bitmap, the canvas, without reading it), in
    their image addresses' low bytes' order"""
    out = [Shape(l) for l in open(os.path.join(HERE, name))
           if l.strip() and l.split()[0] == "B" and l.split()[5] != "1"]
    return sorted(out, key=lambda sh: sh.src & 0xFF)


# level 2's portcullis drop ($A0FC, a one-row OR image, a line at a time,
# rows 81-124: 44 instances, more than a buffer holds): the portcullis
# closed as two columns of it (every 2 rows: 81-123 and 82-124), added by its
# lines at rows 81 and 82 (the set's markers, "column"); its other lines
# dropped. The drop shows closed from its first picture (the game's takes
# about three)
L2_DROP = (0xA0FC, 80)
L2_COLS = ["L A0FC 2 0 81 123 0", "L A0FC 2 0 82 124 0"]
L2_CHB = 0x69
# (level 2's stakes are two images at a place, $A4D8 stored over $A4F0; in
# the band (rows 65-66, over the beam) $A4F0's are the beam's colour 2:
# nothing to show, and as objects they cost a quarter of level 2's time,
# doubled while the view scrolls (FINDINGS "Level 2 as tiles"))
L2_UNSEEN = {0xA4F0}
# (and two drawn once, in the portcullis's drop: out for the shapes' room,
# 127 at most, the four sets' together)
L2_RARE = {(0xA000, 87), (0xA02C, 101)}


def tiles_inventory(scene):
    """a tiles scene's objects (FINDINGS "Level 2 as tiles", "Levels 3 and
    4 as tiles"): its inventory's blits (probes/objinventory.py,
    port/s<N>shapes.txt) but the images its worlds draw (probes/worldlist.py,
    port/worldcfg.py); the ones the game draws after the fighters in front
    (Shape.front); level 2's portcullis columns and left-outs; in their image
    addresses' low bytes' order"""
    C = WC.CFG[scene]
    wimg = {int(l.split()[2], 16) for l in open(os.path.join(HERE, C["out"])) if l.startswith("B ")}
    fr = set(C.get("front", ()))
    lines = [l[3:] if l.startswith("V2 ") else l for l in open(os.path.join(HERE, "s%dshapes.txt" % scene))
             if L.V2 or not l.startswith("V2 ")]       # (a line "V2 ...": V2's only)
    out = [Shape(l) for l in lines
           if l.strip() and l.split()[0] == "B" and (int(l.split()[1], 16) not in wimg or int(l.split()[1], 16) in fr)]
    cols = C.get("front_cols", ())          # (a column drawn piece by piece: one column shape;
    if cols:                                # its first piece's draw is its, a "column" marker)
        csrc = {int(l.split()[1], 16) for l in cols}
        out = [sh for sh in out if sh.src not in csrc] + [Shape(l) for l in cols]
    if scene == 2:
        out = [sh for sh in out if not (sh.src == L2_DROP[0] and sh.row != L2_DROP[1])]
        if not L.V2:                    # (V2: the portcullis one image a buffer, PcCap)
            out += [Shape(l) for l in L2_COLS]
        out = [sh for sh in out if sh.src not in L2_UNSEEN and (sh.src, sh.row) not in L2_RARE]
    fb = set(C.get("figures", ())) | set(C.get("fbox", ())) if L.V2 else set()
    for sh in out:
        sh.front = sh.src in fr
        sh.fbox = sh.src in fb              # (V2: a fighter-box erase takes it out)
        if sh.src in WC.FRONT_OR:           # (in its world too; its front copy an OR)
            sh.mode = KIND_OR
    return sorted(out, key=lambda sh: sh.src & 0xFF)


KIND_OF = {"A": 0, "AR": 1, "M": 2, "MR": 3}


def tiles_set(sid, name, scene, lists, page_bank, more_markers=(), shared=None):
    """a tiles scene's object set from its settings (port/worldcfg.py): its
    worlds one character set at L2_CHB (with the scenes' in shared: one set
    for them all, their streams one), the rooms' zones, the bitmap's pages
    for its windows (level 1's)"""
    C = WC.CFG[scene]
    own = tuple(C["scrolled"]) + tuple(C["rooms"])
    scs = shared or (scene,)
    paths = tuple(WC.CFG[s]["out"] for s in scs)
    worlds = tuple(w for s in scs for w in tuple(WC.CFG[s]["scrolled"]) + tuple(WC.CFG[s]["rooms"]))
    marks = [(src, row, None if kind is None else KIND_OF[kind], w, out_only)
             for src, kind, row, w, out_only in C["markers"]]
    # (levels 3 and 4: $54-$56 too, and the slice pages' columns AK_COLS on,
    # for Akuma's and the hawk's poses, pre-cut: akpose7800)
    blocks = (([(range(L.FT_P0, L.FT_PTOP + 1), L.AK_COLS, L.FT_COLS)] if scene in (3, 4) else [])
              + LEVEL1_BLOCKS + ([ROOM_BLOCKS[1]] if scene in (3, 4) else []))
    return ObjSet(sid, name, (scene,), lists, ROOM_ZONES, 10, lambda r: BLACK,
                  lambda: tiles_inventory(scene), page_bank, blocks, tiles=True,
                  tilesets=[(paths, worlds, L2_CHB, 0)], markers=marks + list(more_markers), own=own,
                  room=C["room_floor"][1] if C.get("room_floor") else None, vwrap=True,
                  mask01=C.get("mask01", False))


class ObjSet(object):
    """a scene page's objects without the blitter (FINDINGS "Levels 2-4
    without the blitter"): its scenes, their play lists' zones (the bottom
    zones, rows 135 on, from ZBOT), the rows' backgrounds, its shapes, its
    page's bank (its images there, or in the art bank), the cart RAM its
    windows go in; tiles (level 1's worlds) or the canvas (rooms: the
    game's fills still drawn into the bitmap, which the zones show under the
    objects; a blit moves its image's instance). A tiles set's character
    sets: (world list, its worlds, CHBASE, first byte); its world markers:
    (image, row or None, kind or None (0-3: right-aligned 1, mirrored 2),
    world (None: level 1's structure, L1Mark; "column": the draw is its
    column shape's, found as one), only out of a room); its
    rooms' floor fill marks its room world; the view wraps (level 2's V,
    0-63 for 1,024 on)"""

    def __init__(self, sid, name, scenes, lists, zones, zbot, rowbg, shapes, page_bank, win_blocks,
                 tiles=False, canvas=False, tilesets=(), markers=(), room=None, vwrap=False, mask01=False,
                 own=None):
        self.sid, self.name, self.scenes, self.lists = sid, name, scenes, lists
        self.zones, self.zbot, self.rowbg, self.shapes = zones, zbot, rowbg, shapes
        self.page_bank, self.win_blocks, self.tiles, self.canvas = page_bank, win_blocks, tiles, canvas
        self.tilesets, self.markers, self.room, self.vwrap = tilesets, markers, room, vwrap
        self.mask01 = canvas or mask01          # (an AND mask's 1s black too: the rooms' floor colour 2)
        self.own = own or tuple(w for ts in tilesets for w in ts[1])    # (the worlds it shows)
        assert zones[zbot][0] == 135 and len(zones) == zbot + 2

    def inventory(self):
        return self.shapes()


# the rooms' play lists ($1908 and $1989 in scenes 3 and 4) make these zones
ROOM_ZONES = [(65, 8), (73, 8), (81, 8), (89, 3), (92, 8), (100, 8), (108, 8), (116, 3), (119, 8),
              (127, 8), (135, 10), (145, 1)]
# their windows: pages $40-$4D (free in scenes 3 and 4: p7800-ramclass.lua;
# the bitmap's pages are the canvas, $73-$7A hold Akuma's and the hawk's
# captured slices) and $54-$56 (the band lists' old pages: windows of 3 lines)
ROOM_BLOCKS = [(range(0x40, 0x4E), 16, 240), (range(0x54, 0x57), 0, 256)]


FB_TOP_ = 65
SOLID_W = 20
SKY_BYTE = 0xAA                 # (the sky's rows: colour 2, palette 1)


def special(shapes):
    """the shape numbers of the sky's, the floor's and the rails' strips"""
    return {"L1_SKYS": next(i for i, sh in enumerate(shapes) if sh.kind == "S" and sh.src == 0xAA),
            "L1_FLRS": next(i for i, sh in enumerate(shapes) if sh.kind == "S" and sh.src == 0x55),
            "L1_RAILS": next(i for i, sh in enumerate(shapes) if sh.tile and not sh.sky),
            "L1_SKYRAILS": next(i for i, sh in enumerate(shapes) if sh.sky)}


def pixels(get, sh):
    """{screen row: [2-bit pixels]} of a shape (get(bank, address) -> byte),
    and its width in bytes"""
    if sh.kind == "S":
        return {r: [(sh.src >> (6 - 2 * (k & 3))) & 3 for k in range(4 * SOLID_W)]
                for r in range(sh.row, sh.lim)}, SOLID_W
    rows, iw = get(sh.bank, sh.src), get(sh.bank, sh.src + 1)
    w = RAILS_W if sh.tile else iw
    out = {}
    for t in sh.tops():
        for r in range(rows):
            px = []
            for k in range(4 * w):
                kk = k % (4 * iw) if sh.tile else (4 * w - 1 - k if sh.mir else k)
                b = get(sh.bank, sh.src + 2 + r * iw + (kk >> 2))
                px.append((b >> (6 - 2 * (kk & 3))) & 3)
            out[t + r] = px
    if sh.sky:
        for r in range(sh.lim, sh.row):
            out[r] = [2] * (4 * w)
    return out, w


def conv(v, mode, bg):
    """a pixel as its window holds it"""
    if mode == KIND_AND:
        # (the mask's black: palette PAL_MASK's 1; in the canvas its 1s too,
        # which AND the floor's stripes, colour 2, to black)
        return 1 if (v < 2 if CUR and CUR.mask01 else v == 0) else 0
    if mode == KIND_OR:
        return v
    if v == bg:
        return 0
    return bg if v == 0 else v


def parts(z0, h):
    """a zone's parts by background: [(first row, last row + 1, background)]"""
    out, r = [], z0
    while r < z0 + h:
        bg = row_bg(r)
        e = r
        while e < z0 + h and row_bg(e) == bg:
            e += 1
        out.append((r, e, bg))
        r = e
    return out


# the zone parts the windows are made for: a zone's rows by background (zone
# 0, rows 65-72: its sky rows and its fence's), and after them, if it has
# more than one, the whole zone (WHOLE: a shape whose parts there share a
# palette has one window, one object, for them all: MARIA's time).
# (zone, first row, lines, the part's first row, past its last, background)
WHOLE = 0xFF                    # (its background: none of its own)
def zone_parts():
    out = []
    for zi, (z0, h) in enumerate(ZONES):
        ps = parts(z0, h)
        for a, e, bg in ps:
            out.append((zi, z0, h, a, e, bg))
        if len(ps) > 1:
            out.append((zi, z0, h, z0, z0 + h, WHOLE))
    return out


PARTS = zone_parts()
ART = 6                        # (an image in the art bank: its shape's flag)


T_OF_PAL = {1: BLACK, 2: SKY, 3: FLOOR}   # a palette's colour shown clear (0)


def clear_colour(sh, px, a, e, bg):
    """the colour a stored shape's part (rows a to e) shows clear: one it
    doesn't use there, so it is opaque as the blitter's store drew it (black,
    then the sky, then the floor's colour: palettes 1, 2, 3 hold the other
    three); with all four, the least used of those (its overlay draws it)"""
    used = {v for r in range(a, e) if r in px for v in px[r]}
    for t in (BLACK, SKY, FLOOR):
        if t not in used:
            return t
    cnt = {t: sum(px[r].count(t) for r in range(a, e) if r in px) for t in (BLACK, SKY, FLOOR)}
    return min((BLACK, SKY, FLOOR), key=lambda t: (cnt[t], t))


def windows(get, sh):
    """{part: (data (its zone's lines x w), palette)} of a shape, the
    all-clear ones left out, and its width; a part's lines outside its rows
    are 0"""
    px, w = pixels(get, sh)
    out = {}
    for p, (zi, z0, h, a, e, bg) in enumerate(PARTS):
        if bg == WHOLE:
            # the zone's parts before it, if more than one has a window and
            # all theirs share a palette: their windows as one (their lines
            # are each other's 0s)
            mine = [q for q in range(p) if PARTS[q][0] == zi and q in out]
            if len(mine) > 1 and len({out[q][1] for q in mine}) == 1:
                data, pal = bytes(w * h), out[mine[0]][1]
                for q in mine:
                    data = bytes(x | y for x, y in zip(data, out.pop(q)[0]))
                out[p] = (data, pal)
            continue
        if not any(a <= r < e for r in px):
            continue
        t = clear_colour(sh, px, a, e, bg) if sh.mode in (KIND_STORE, KIND_OVER) else bg
        if sh.mode == KIND_OVER:
            used = {v for r in range(a, e) if r in px for v in px[r]}
            if len(used) < 4:
                continue                    # (an overlay only for four-colour parts)
        data = bytearray()
        for r in range(z0, z0 + h):
            row = px.get(r) if a <= r < e else None
            for k in range(w):
                b = 0
                if row:
                    for q in range(4):
                        v = row[4 * k + q]
                        if sh.mode == KIND_OVER:
                            o = OVER_OF_PAL[PAL_OF_OVER[t]][1] if v == t else 0
                        else:
                            o = conv(v, sh.mode, t)
                        b |= o << (6 - 2 * q)
                data.append(b)
        if any(data):
            pal = PAL_MASK if sh.mode == KIND_AND else (1 if sh.mode == KIND_OR else (
                PAL_OF_OVER[t] if sh.mode == KIND_OVER else PAL_OF[t]))
            out[p] = (bytes(data), pal)
    return out, w


def palette(sh, p):
    if sh.mode == KIND_AND:
        return PAL_MASK
    if sh.mode == KIND_OR:
        return 1
    return PAL_OF[PARTS[p][5]]


class Pages(object):
    """cart RAM's window pages: a window of h lines at h consecutive pages
    (line g at page T - g), the same low byte"""

    def __init__(self):
        self.used, self.data = {}, {}
        self.reserved = set()                  # (page * 256 + byte: reserve's, the tiles' characters)
        for pages, lo, hi in WIN_BLOCKS:
            for p in pages:
                self.used[p] = bytearray(b"\x01" * lo + bytes(hi - lo) + b"\x01" * (256 - hi))
                self.data[p] = bytearray(256)
        for p, flags in PRE_USED.items():       # (V2: the text's, in banks 0 and 4)
            if p in self.used:
                self.used[p] = bytearray(u | f for u, f in zip(self.used[p], flags))

    def reserve(self, page, lo, data):
        """data at page's byte lo on (the tiles' characters: their line
        pages from byte 0, the heads level 1 doesn't use)"""
        for k, b in enumerate(data):
            if self.used[page][lo + k] and lo + k >= WIN_LO:
                raise SystemExit("level 1: cart RAM $%04X taken twice" % (page * 256 + lo + k))
            self.used[page][lo + k] = 1
            self.data[page][lo + k] = b
            self.reserved.add(page * 256 + lo + k)

    def put(self, h, w, data, prefer=()):
        """(prefer: blocks tried first: the rooms' map rows in $54-$56, so
        the 8-line windows keep the tall blocks)"""
        for pages, lo, hi in list(prefer) + [b for b in WIN_BLOCKS if b not in prefer]:
            for c in range(lo, hi + 1 - w):        # (a column at a time: fits them all)
                for t in range(pages[-1], pages[0] + h - 2, -1):
                    if not any(self.used[t - g][c + k] for g in range(h) for k in range(w)):
                        for g in range(h):
                            self.used[t - g][c:c + w] = b"\x01" * w
                            self.data[t - g][c:c + w] = data[g * w:(g + 1) * w]
                        return t, c
        raise SystemExit("level 1: no room in cart RAM for a %d x %d window" % (h, w))

    def free(self):
        return sum(256 - sum(u) for u in self.used.values())

    def size(self):
        return sum(hi - lo for pages, lo, hi in WIN_BLOCKS for p in pages)


def layout(get, shapes, pre=None):
    """every shape's windows placed: ([(shape, w, {part: (T, C)})], Pages);
    identical windows once, the tallest, then widest, first (pre(pages):
    what goes in first: the tiles)"""
    pg, at = Pages(), {}
    if pre:
        pre(pg)
    shapes = with_overlays(get, shapes)
    pixels_get[0] = lambda sh: pixels(get, sh)[0]
    allw = [(sh,) + windows(get, sh) for sh in shapes]
    every = {}
    for sh, ws, w in allw:
        for p, (data, pal) in ws.items():
            every[(PARTS[p][2], data)] = w
    for (h, data), w in sorted(every.items(), key=lambda t: (-t[0][0], -t[1], t[0][1])):
        at[(h, data)] = pg.put(h, w, data)
    return [(sh, w, {p: at[(PARTS[p][2], d)] + (pal,) for p, (d, pal) in ws.items()}) for sh, ws, w in allw], pg


pixels_get = [None]          # (tables: the shapes' rows, set by layout)


def numbered(lay):
    """the layout's shapes as numbered (an overlay is its base's, not one)"""
    return [sh for sh, w, place in lay if sh.mode != KIND_OVER]


def tables(lay):
    """the shapes' table fields (lists) and each one's entries ((T, C) for
    each part from its first to its last; T 0: none; a shape with an
    overlay: then the overlay's for the same parts)"""
    f = {k: [] for k in ("SLO", "SHI", "ROW", "FL", "LIM", "W", "P0", "NE", "ROWE", "FR", "FB")}
    entries = []
    ent = lambda place, first, last: [
        v for p in range(first, last + 1)
        for v in ((((place[p][0] - WIN_BASE) | place[p][2] << 6), place[p][1]) if p in place else (0, 0))]
    for sh, w, place in lay:
        if sh.mode == KIND_OVER:
            first, last = f["P0"][-1], f["P0"][-1] + f["NE"][-1] - 1
            if not set(place) <= set(range(first, last + 1)) or w != f["W"][-1]:
                raise SystemExit("level 1: an overlay's parts or width unlike its base's")
            entries[-1] += ent(place, first, last)
            continue
        first, last = min(place), max(place)
        f["ROWE"].append(max(pixels_get[0](sh)) + 1)
        f["SLO"].append(sh.src & 0xFF)
        f["SHI"].append(sh.src >> 8)
        f["ROW"].append(sh.row)
        f["FL"].append((0x80 if sh.mir else 0) | (0x40 if sh.kind == "L" else 0) | (0x20 if sh.bank == ART else 0)
                       | (0x10 if sh.tile else 0) | (0x08 if sh.kind == "S" or sh.sky else 0) | (0x04 if sh.over else 0)
                       | sh.mode)
        f["LIM"].append(sh.lim or 0)
        # (the emission's passes: 1 before the fighters, 2 after; 3 after,
        # and in its world's tiles too: drawn only over a fighter, L1FrHit;
        # level 1's set only: the attract loop's has the torii's front post
        # as a column of its own, not in its tiles, FINDINGS "The hardware
        # test, 2026-10-17")
        f["FR"].append((3 if sh.src in L1_FRONT and CUR.sid == 0 else 2) if sh.front else 1)
        f["W"].append(w)
        f["FB"].append(1 if getattr(sh, "fbox", False) else 0)
        f["P0"].append(first)
        f["NE"].append(last - first + 1)
        # each part: its page (less $40) with its palette in bits 6-7 (never
        # 0: 0 is no window), its low byte
        entries.append(ent(place, first, last))
    # each shape's zones: its first, past its last (the emission passes over
    # it in every other zone)
    f["ZA"], f["ZE"] = [], []
    for i, e in enumerate(entries):
        zs = [PARTS[f["P0"][i] + j % f["NE"][i]][0] for j in range(len(e) // 2) if e[2 * j]]
        f["ZA"].append(min(zs))
        f["ZE"].append(max(zs) + 1)
    return f, entries


def first_of_lo(f):
    """the capture's index: by an image address's low byte, the first shape
    with it ($FF none; the shapes are in its order: inventory)"""
    out = [0xFF] * 256
    for i in range(len(f["SLO"]) - 1, -1, -1):
        out[f["SLO"][i]] = i
    if f["SLO"] != sorted(f["SLO"]):
        raise SystemExit("level 1: the shapes aren't in their image addresses' low bytes' order")
    return out


def first_of_lo32(f):
    """the capture's index, smaller: by an image address's low byte / 8, the
    first shape with a low byte at or past 8 x it ($FF none); L1Find goes on
    from there past the lower ones"""
    first_of_lo(f)                      # (its order checked)
    return [next((i for i, lo in enumerate(f["SLO"]) if lo >= 8 * k), 0xFF) for k in range(32)]


def generate(get, f, entries):
    """the 6502 generator (L1Gen) step for step: {address: byte} it writes"""
    out = {}
    rev = lambda b: sum(((b >> (6 - 2 * i)) & 3) << (2 * i) for i in range(4))
    for s in range(len(f["SLO"])):
        src, row, fl, lim, w = f["SLO"][s] | f["SHI"][s] << 8, f["ROW"][s], f["FL"][s], f["LIM"][s], f["W"][s]
        bank = ART if fl & 0x20 else (CUR.page_bank if CUR else 1)
        rows, iw = (0, 1) if fl & 0x18 == 0x08 else (get(bank, src), get(bank, src + 1))
        ne = f["NE"][s]
        for j in range(len(entries[s]) // 2):
            if j == ne:                     # (its overlay's entries: mode 3)
                fl = fl & ~7 | KIND_OVER
            T, C = entries[s][2 * j], entries[s][2 * j + 1]
            if not T:
                continue
            pal = T >> 6
            bg = T_OF_PAL[pal]
            T = (T & 0x3F) + WIN_BASE
            zi, z0, h, a, e, _ = PARTS[f["P0"][s] + j % ne]
            for g in range(h):
                r = z0 + g
                d = r - row
                line = None
                if fl & 0x18 == 0x18 and r < row:      # (the sky above the rails)
                    for c in range(w):
                        out[(T - g) * 256 + C + c] = SKY_BYTE if (a <= r < e and lim <= r) else 0
                    continue
                if fl & 0x18 == 0x08:
                    for c in range(w):
                        out[(T - g) * 256 + C + c] = src & 0xFF if (a <= r < e and row <= r < lim) else 0
                    continue
                if a <= r < e and d >= 0:
                    k = d
                    if fl & 0x40:
                        if d >> 1 <= (lim - row + 1) >> 1:
                            k = d & 1
                        else:
                            k = None
                    if k is not None and k < rows:
                        line = k
                for c in range(w):
                    if line is None:
                        v = 0
                    else:
                        sc = c % iw if fl & 0x10 else (w - 1 - c if fl & 0x80 else c)
                        b = get(bank, src + 2 + line * iw + sc)
                        if fl & 0x80:
                            b = rev(b)
                        v = 0
                        for q in range(4):
                            px = (b >> (6 - 2 * q)) & 3
                            if fl & 3 == KIND_OVER:
                                oc, ov = OVER_OF_PAL[pal]
                                o = ov if px == oc else 0
                            elif fl & 3 == KIND_AND:
                                o = 1 if (px < 2 if CUR and CUR.mask01 else px == 0) else 0
                            elif fl & 3 == KIND_OR:
                                o = px
                            else:
                                o = 0 if px == bg else (bg if px == 0 else px)
                            v |= o << (6 - 2 * q)
                    out[(T - g) * 256 + C + c] = v
    return out


# its RAM (L1RAM: the fast fill's, 369 bytes, never run in level 1): each
# buffer's view (V: 2 bytes) and instance count, a change flag, the
# generator's scratch (only at the load: its entries over the lists), each
# buffer's instances (shape, x: L1_NMAX)
L1_NMAX = 24                    # (the clean run's most: 17)
# the generator's scratch (the load's only: over the lists' pieces, past the
# instances)
GEN_VARS = [("L1G_SET", 1), ("L1G_SF", 1), ("L1G_AM", 1), ("L1G_TS", 1), ("L1G_S", 1), ("L1G_P", 1), ("L1G_NE", 1),
            ("L1G_FL", 1), ("L1G_W", 1), ("L1G_SRC", 2), ("L1G_ROW", 1), ("L1G_LIM", 1),       # (L1GenKL's order)
            ("L1G_J", 1), ("L1G_T", 1), ("L1G_C", 1), ("L1G_G", 1),
            ("L1G_H", 1), ("L1G_A", 1), ("L1G_EE", 1), ("L1G_BG", 1), ("L1G_Z0", 1), ("L1G_ROWS", 1),
            ("L1G_IW", 1), ("L1G_IN", 1), ("L1G_OUT", 1), ("L1G_K", 1), ("L1G_R", 1), ("L1G_IB", 1),
            ("L1G_OC", 1), ("L1G_OV", 1), ("L1G_KE", 1)]
RAM_VARS = [("L1_V", 4), ("L1_N", 2), ("L1_DIRTY", 2),
            ("L1_JV", 2), ("L1_K", 1), ("L1_B", 1), ("L1_S", 1), ("L1_X", 1), ("L1_ZN4", 1),
            ("L1_WLD", 2), ("L1_T0", 1), ("L1_T1", 1), ("L1_T2", 1), ("L1_T3", 1), ("L1_T4", 1),
            ("L1C_MIR", 1), ("L1B_KIND", 1), ("L1_ROW", 1), ("L1_SRC", 2), ("L1_FLM", 1), ("L1_W", 1),
            ("L1_P0", 1), ("L1_NE", 1), ("L1_FL", 1), ("L1_E", 1), ("L1_WR", 1), ("L1_WY", 1), ("L1_WMAX", 1),
            ("L1_C0", 1), ("L1_C1", 1), ("L1_R0", 1), ("L1_R1", 1), ("L1_I", 1), ("L1_SV", 2),
            ("L1F_PAT", 1), ("L1_ZK", 1), ("L1_SX", 1), ("L1_FX", 1), ("L1_FY", 1), ("L1_F06", 1),
            ("L1_SET", 1), ("L1_ZB", 1), ("L1_ZBT", 1), ("L1_SF", 1), ("L1_RW", 1), ("L1_TP", 1),
            ("L1_FP", 1), ("L1_FS", 1),
            ("AKP_ON", 1), ("AKP_REND", 1), ("AKP_K", 1), ("AKP_N", 1), ("AKP_P", 2), ("AKP_S", 2),
            ("AKP_SB", 2), ("AKP_KEY", 6), ("AKP_T", 6), ("AKP_C", 6), ("AKP_COLS", 1),
            ("L1_KB", 1), ("L1_KE", 1), ("L1_KF", 1),
            ("L1_SHA", L1_NMAX), ("L1_XA", L1_NMAX), ("L1_SHB", L1_NMAX), ("L1_XB", L1_NMAX)]
# level 1's lists in console RAM (the user: display lists out of cart RAM):
# each buffer's band zones' in its pieces (BandWrite: the title's and story's
# lists' RAM, TS_DLA/TS_DLB, unused while level 1 shows; then its share of
# L1RAM past the variables), its two bottom zones' (rows 135-144 and 145, not
# band zones: L1Flip writes them, L1BOT_N bytes each) in its DLL page's tail
# (level 1's DLLs end at $B7: FINDINGS "Level 1: the lists out of cart RAM")
L1SEG_TS = ((0x2410, 0x24C0), (0x2510, 0x2600))     # (the row lists' room's rest too: 10 bytes
                                                     # theirs in level 1)
L1SEG_DLL = ((0x22E7, 0x2300), (0x23E7, 0x2400))     # (the DLL tails past the bottom lists)
# (and console RAM nothing uses while level 1 runs, measured: p7800-ramuse.lua
# over the clean run and every scene: A's $1B4E-$1B7F (past the Akuma
# tables) and $1852-$187F (below the zero page's swap buffer); B's
# $1F46-$1F77 (the mode-8 rows' tail: expanded afresh wherever they show)
# and $1E85-$1EB1 (the column routine's and the fast fill's scratch: level 1
# captures those draws instead)
L1SEG_MORE = (((0x1B4E, 0x1B80), (0x1852, 0x1880), (0x1F00, 0x1F18)),
              ((0x1F46, 0x1F78), (0x1E85, 0x1EB2), (0x27E7, 0x2800)))   # (A's third: the mode-8
                                                                      # rows' start; B's: past
                                                                      # the NMI's stub)
# (and while console RAM is short, what doesn't fit there in cart RAM's old
# area for them: to go (FINDINGS "Level 1: the lists out of cart RAM"))
L1SEG_CART = ((0x7310, 0x7600), (0x7610, 0x7900))
# levels 2-4's band lists' pieces (L1SG_* rows 16, 24; S_BLPC $10): the free
# runs the census found in scenes 2-4 (p7800-ramuse.lua, the kit's scripted
# runs), less the glyphs' block ($1B80-$1DF5, in when text is up), the
# static lists at $2780 and the DLL pages' first $80 (their DLLs: about 40
# entries). The allocator's bytes (L1_SG, L1_SGP, L1_SGX, L1_SGK) at
# SG_VARS: free in every gameplay scene, not in L1RAM (the fast fill's code
# outside level 1). Not the bottom zones' lists of a tiles set (level 2's:
# L1Bottom's, at L1BOT/L1BOTB, L1BOT_N each)
# (and, as tiles sets, the fast fill's RAM, L1RAM to $277F, as level 1's:
# their fills are captured, the fill never runs)
# (now port/consoleplan_out.py's: each group's pieces in the room its scenes
# leave, FINDINGS "Console RAM laid out scene by scene")
import consoleplan_out as CP                    # noqa: E402
BMSEG_A, BMSEG_B = CP.G10_BAND_A, CP.G10_BAND_B
SG_VARS = CP.SGV_AT               # (console RAM now)
# scene 0's (the attract mode's demo fight; S_BLPC $20: L1SG_* rows 32, 40):
# free in all of scene 0 after the boot (the title, the story, the demo)
# (not the bottom zones' lists: scene 0 has a tiles set, FINDINGS "The
# attract loop as tiles": L1Bottom's at L1BOT/L1BOTB, L1BOT_N each)
# (and the fast fill's old RAM, L1RAM to $277F, as levels 2-4's: no scene
# copies the fill there any more)
S0SEG_A, S0SEG_B = CP.G20_BAND_A, CP.G20_BAND_B
L1BOT, L1BOTB, L1BOT_N = 0x22B7, 0x23B7, 24     # (24 a zone: the tiles, three objects: the rooms' posts reach row 136)


def part_tables():
    """the emission's tables by zone part: its lines less 1; and by zone: its
    first part, its parts"""
    return {"L1Q_HM1": [p[2] - 1 for p in PARTS],
            "L1Q_ZP0": [next(i for i, p in enumerate(PARTS) if p[0] == z) for z in range(len(ZONES))],
            "L1Q_ZNP": [sum(1 for p in PARTS if p[0] == z) for z in range(len(ZONES))]}


# level 1's variables: CPU data, in cart RAM (the blitters' old room, past
# the top lists' state), so L1RAM's start holds the top's lists (TPSEG_L1*)
L1VARS = CP.L1VARS_AT             # (console RAM now)
# (in three blocks, for console RAM's room: FINDINGS "The CPU's data out of
# cart RAM": the instances' four tables as one, L1OBJ, B's at A's + 2 x
# L1_NMAX; the other variables in two halves of L1VARS_N bytes each,
# L1VARS and L1VARB, cleared by one loop)
L1OBJ_T = ("L1_SHA", "L1_XA", "L1_SHB", "L1_XB")


def l1var_split():
    """the variables but the instances' tables: (first half, second half,
    each half's size)"""
    rest = [(nm, n) for nm, n in RAM_VARS if nm not in L1OBJ_T]
    half = (sum(n for _, n in rest) + 1) // 2
    a, b, s = [], [], 0
    for nm, n in rest:
        if not b and s + n <= half:
            a.append((nm, n))
            s += n
        else:
            b.append((nm, n))
    return a, b, max(s, sum(n for _, n in b))
# the top lists' pieces past L1RAM's (the census: free in level 1 and scene 6)
# (and the DLL pages' room past their DLLs, about 37 entries since the
# merged zones, before the bottom lists at L1BOT/L1BOTB)
TPSEG_L1_MORE = (((0x2270, 0x22B7), (0x1A57, 0x1A80), (0x24D0, 0x24E1)),
                 ((0x2370, 0x23B7), (0x1EB6, 0x1EE6), (0x1812, 0x1820)))


def ram_equates(base):
    out = {"L1RAM": base, "L1_NMAX": L1_NMAX, "L1VARS": L1VARS, "L1VARB": CP.L1VARB_AT,
           "L1OBJ": CP.L1OBJ_AT, "L1OBJ_N": 4 * L1_NMAX}
    first, second, m = l1var_split()
    for part, v in ((first, CP.L1VARS_AT), (second, CP.L1VARB_AT)):
        for name, n in part:
            out[name] = v
            v += n
    v = CP.L1OBJ_AT
    for name, n in RAM_VARS:
        if name in L1OBJ_T:
            out[name] = v
            v += n
    assert [out[t] for t in L1OBJ_T] == [CP.L1OBJ_AT + k * L1_NMAX for k in range(4)]
    out["L1VARS_N"] = m                     # (L1Gen clears both halves: these bytes each)
    for k in range(7):                      # (level 1's and the vs fight's top pieces: consoleplan)
        for nm, seg in (("TPSA", CP.G00_TOP_A), ("TPSB", CP.G00_TOP_B)):
            lo, hi = seg[k] if k < len(seg) else (0, 0)
            out["%s%d" % (nm, k)], out["%s%dE" % (nm, k)] = lo, hi
    out["L1G_E"] = out["L1_SHA"]            # (the generator's entries and fetches: over the lists,
    out["L1G_BUF"] = out["L1_SHB"]          # each over a buffer's two: L1_NB bytes)
    out.update({"L1_NB": 2 * L1_NMAX, "L1BOT": L1BOT, "L1BOTB": L1BOTB, "L1BOT_N": L1BOT_N})
    out.update({"L1_SG": SG_VARS, "L1_SGP": SG_VARS + 1, "L1_SGX": SG_VARS + 15, "L1_SGK": SG_VARS + 16})
    for k in range(7):
        for nm, seg in (("L1SC", BMSEG_A), ("L1SD", BMSEG_B), ("L1SE", S0SEG_A), ("L1SF", S0SEG_B)):
            lo, hi = seg[k] if k < len(seg) else (0, 0)
            out["%s%d" % (nm, k)], out["%s%dE" % (nm, k)] = lo, hi
    # the generator's scratch at L1RAM's start (the load's only)
    g = base
    for name, n in GEN_VARS:
        out[name] = g
        g += n
    for k in range(7):                      # (level 1's and the vs fight's band pieces: consoleplan)
        for nm, seg in (("L1SA", CP.G00_BAND_A), ("L1SB", CP.G00_BAND_B)):
            lo, hi = seg[k] if k < len(seg) else (0, 0)
            out["%s%d" % (nm, k)], out["%s%dE" % (nm, k)] = lo, hi
    return out


LEVEL1_ZONES, LEVEL1_ZBOT, LEVEL1_BLOCKS = ZONES, ZBOT, WIN_BLOCKS
L1SET = ObjSet(0, "level 1", (1, 6), LISTS, LEVEL1_ZONES, LEVEL1_ZBOT, row_bg_l1, inventory, 1,
               LEVEL1_BLOCKS, tiles=True,
               tilesets=[("l1world.txt", ("0", "0b", "1", "c"), L.L1_CHB, 0)],
               markers=[(RAILS, None, None, None, False)], room="c")
# level 2 (FINDINGS "Level 2 as tiles"): level 1's machinery; the bitmap's
# pages its windows' as in level 1; one character set for its three worlds
# (123 characters, the rooms' figures objects), at $69-$72 from byte 0 (the
# band zones' list heads, unused with tiles as level 1's $64-$6D): $58-$68
# one block for the windows
L2SET = tiles_set(3, "level 2", 2, (0x1908, 0x19A2), 2,
                  [] if L.V2 else                             # (V2: the portcullis one image, PcCap)
                  [(0xA0FC, 81, None, "column", False),       # (the portcullis's drop:
                   (0xA0FC, 82, None, "column", False)])      # its two columns)
# levels 3 and 4 (FINDINGS "Levels 3 and 4 as tiles"): as level 2, their
# rooms' AND masks black where 0 or 1 (as the canvas's)
# the attract loop (scene 0, FINDINGS "The attract loop as tiles"): level 1's
# lists and zones (its play lists show the cell, the princess's room and
# level 1's gate alike), its worlds and markers from port/worldcfg.py, a
# column drawn piece by piece one column shape (its first piece's draw the
# column's: a "column" marker)
def attract_set(sid):
    C = WC.CFG[0]
    marks = [(src, row, None if kind is None else KIND_OF[kind], w, out_only)
             for src, kind, row, w, out_only in C["markers"]]
    marks += [(int(l.split()[1], 16), int(l.split()[4]), None, "column", False) for l in C.get("front_cols", ())]
    own = tuple(C["scrolled"]) + tuple(C["rooms"])
    return ObjSet(sid, "attract", (0,), LISTS, LEVEL1_ZONES, LEVEL1_ZBOT, row_bg_l1,
                  lambda: tiles_inventory(0), 0, LEVEL1_BLOCKS, tiles=True,
                  tilesets=[((C["out"],), own, L2_CHB, 0)], markers=marks, own=own,
                  room=C["room_floor"][1], vwrap=False, mask01=False)


SETS = [L1SET,
        tiles_set(1, "level 3", 3, (0x1908, 0x1989), 3, shared=(3, 4)),     # (one character set: 90
        tiles_set(2, "level 4", 4, (0x1908, 0x1989), 4, shared=(3, 4)),     # characters, level 4's rows
                                                                             # level 3's)
        L2SET,
        attract_set(4)]


SETS_ON = (0, 1, 2, 3, 4)       # (the sets in use: levels 1, 3, 4 and 2; the attract loop)


def use(st):
    """the set the module's functions work on (its zones, parts, rows'
    backgrounds, cart RAM)"""
    global CUR, ZONES, ZBOT, LISTS, PARTS, WIN_BLOCKS
    CUR = st
    ZONES, ZBOT, LISTS, WIN_BLOCKS = st.zones, st.zbot, st.lists, st.win_blocks
    PARTS = zone_parts()


def cart_get(path):
    """get(bank, address) from a built cart (its CPU half)"""
    d = open(path, "rb").read()[128:]

    def get(bank, a):
        if a >= 0xC000:
            return d[len(d) // 2 - 0x4000 + a - 0xC000]
        return d[bank * 0x4000 + a - 0x8000]
    return get


if __name__ == "__main__":
    get = cart_get(os.path.join(HERE, "..", "work", "karateka7800.a78"))
    lay, pg = layout(get, inventory())
    nwin = sum(len(ws) for sh, w, ws in lay)
    f, ent = tables(lay)
    gen = generate(get, f, ent)
    bad = [a for a, v in gen.items() if pg.data[a >> 8][a & 0xFF] != v]
    print("the generator's twin: %d bytes written, %d unlike the layout" % (len(gen), len(bad)))
    print("tables: %d shapes, %d entry bytes" % (len(f["SLO"]), sum(len(e) for e in ent)))
    print("%d shapes, %d windows; %d bytes used, %d free" % (len(lay), nwin, pg.size() - pg.free(), pg.free()))
    import build7800 as B
    import dis as D
    mems = {s: D.memory(s) for s in L.SCENES}
    xdl = B.shared_display_lists(B.xe_display_lists(), mems)
    for s in (1, 6):
        for at in sorted(xdl.get(s, ())):
            d = B.space_dlis(B.describe(mems[s], at)[0])
            print(s, "$%04X" % at, buffer_zones(d))


if L.V2:  # (V2_BLOCKS for every set)
    for _st in SETS:
        _st.win_blocks = V2_BLOCKS
