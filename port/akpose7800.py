"""Akuma's and the hawk's poses pre-cut at a scene's load (FINDINGS "Akuma
and the hawk pre-cut at load"). FtEmitAk's slices were copied into the
slice pages at every emission; now each pose (port/akposes.txt,
probes/akposes.py) has its cells in the scene's cart RAM, cut once at the
load by the same code (AkPre: FtPlain, FtObj in render mode), and an
emission of a pose found in the table (AkLook) only points its objects
there. A pose not found is copied as before.

A pose: its image (the sprite of a pair), its mask ($14/$15 of a pair, 0
none), flags (S_FMIR), row (FP_ROW); its cells as FtPlain cuts it: the
band's rows (FB_TOP to BAND_ZEND) at the fighters' grid (fighters7800.ZONES),
each a window of the cell's lines x the image's width (line g at page T - g).

The table (bank AK_TABB, 4, read through FtRead) in chunks: each its poses
(a byte), the next chunk's address (0: none), then each pose: image lo, hi,
mask lo, hi, flags, row, its image's bank, its cells n, then n (T, C)."""
import os

import fighters7800 as F
import layout7800 as L

HERE = os.path.dirname(os.path.abspath(__file__))
FB_TOP, BAND_ZEND = 65, 134
KEY_N = 6                       # (image lo, hi, mask lo, hi, flags, row: AkLook's key)
TAB_BANK = {3: 3 if L.V2 else 0, 4: 4}   # (V2: each in its scene's own page: no switch in play)
                                # (each scene's table and its search, AkFind: the hawk's in bank 0,
                                # Akuma's in bank 4, both safe in levels 3 and 4: their MARIA copies
                                # differ only in the top data's groups of levels 1 and 2)
CHUNK = 40 if L.V2 else 60     # (a table's chunk at most: bank 4's free runs; V2's
                                # smaller since the held list's code took fixed-bank room:
                                # FINDINGS "The switch frames: built outside the NMI")


def load(path=os.path.join(HERE, "akposes.txt")):
    """{scene: [(image, mask, flags, row)]}"""
    out = {}
    for l in open(path):
        p = l.split()
        if p and p[0] == "P":
            out.setdefault(int(p[1]), []).append((int(p[2], 16), int(p[3], 16), int(p[4], 16), int(p[5])))
    return out


def image_bank(scene, a):
    """the bank BlitBank reads image a from in scene's page: the art bank for
    an art copy's page ($A0-$BF, the scene's page map), else the scene's"""
    if 0xA000 <= a < 0xC000:
        for lo, hi, d, scenes in L.ART_COPIES + [c for c in L.SPRITE_COPIES if c[0] + c[2] < 0xC000]:
            if scene in scenes and (lo + d) >> 8 <= a >> 8 <= (hi - 1 + d) >> 8:
                return L.ART_BANK
        return L.SCENE_BANK[scene]
    return L.ART_BANK


def cells(row, rows):
    """FtPlain's cells for rows row to row + rows - 1: [(cell, its lines)]"""
    out, r, end = [], row, row + rows
    while r < end:
        if r > BAND_ZEND:
            break
        if r < FB_TOP:
            r += 1
            continue
        z = next(i for i, (a, b) in enumerate(F.ZONES) if a <= r <= b)
        out.append((z, F.ZONES[z][1] - F.ZONES[z][0] + 1))
        r = F.ZONES[z][1] + 1
    return out


AKUMA_SCENE = 4                 # (V2: Akuma's poses coloured, FINDINGS "Akuma's red")


def akuma(pose, scene):
    """(V2) one of Akuma's poses to colour: a pair or a sprite alone, in his
    scene (a mask alone, flags bit 5 and no mask, stays his black)"""
    img, msk, fl, row = pose
    return L.V2 and scene == AKUMA_SCENE and (bool(msk) or not fl & 0x20)


def coloured(pose, scene=None):
    """(V2) a hawk's pair (a sprite and its mask, flags bit 4) or Akuma's
    pose: cut in 160B in the upper palette group, its cells twice as wide
    (FINDINGS "The hawk in 160B", "Akuma's red"): P4 skin, black, white;
    the hawk's grey in P6, Akuma's grey and reds in P7"""
    img, msk, fl, row = pose
    return L.V2 and (bool(msk) and bool(fl & 0x10) or akuma(pose, scene))


def reserve(pg, get, scene, poses):
    """each pose's cells' windows in the set's cart RAM (Pages.put, zeros:
    the load cuts them): [(pose, bank, [(T, C)])]"""
    out = []
    for img, msk, fl, row in poses:
        bank = image_bank(scene, img)
        rows, w = get(bank, img), get(bank, img + 1)
        if msk:
            rows = max(rows, get(image_bank(scene, msk), msk))
        cs = []
        wb = 2 * w if coloured((img, msk, fl, row), scene) else w     # (160B: two bytes a column)
        for z, h in cells(row, rows):
            t, c = pg.put(h, wb, bytes(h * wb))
            cs.append((t, c))
        out.append(((img, msk, fl, row), bank, cs))
    return out


def pose_bytes(pose):
    (img, msk, fl, row), bank, cs = pose
    b = bytes([img & 0xFF, img >> 8, msk & 0xFF, msk >> 8, fl, row] + ([] if L.V2 else [bank]) + [len(cs)])
    # (V2: no image bank: AkFind never read it, and only v1's AkPre, the load's
    # cut, did; FINDINGS "The hardware test")
    return b + bytes(v for t, c in cs for v in (t, c))


def table(res, chunk=CHUNK):
    """the table in chunks (each a piece of its own: bank L1_GEN's runs are
    short): [[poses' bytes]], each chunk's header (poses, the next chunk's
    address) the assembler's"""
    out, cur, n = [], [], 0
    for p in res:
        b = pose_bytes(p)
        if cur and n + len(b) > chunk:
            out.append(cur)
            cur, n = [], 0
        cur.append(b)
        n += len(b)
    if cur:
        out.append(cur)
    return out


# ---------------------------------------------------------------- the cut
# (FINDINGS "The ROM by scene: step 1": the load's cutting, AkPre, as the
# build's: so the poses' cells can be made in ROM)
def _mir(b):
    """FT_MIR (the game's mirrored-byte table, $F500): the pixels reversed"""
    return sum(((b >> (6 - 2 * i)) & 3) << (2 * i) for i in range(4))


def cut(get, pose, scene=None):
    """AkPre's cutting of one pose, step for step (FtPlain in render mode,
    FtObj's place from the table, FtCopy, FtRow/FtRowK/FtRowM/FtRowP2):
    {cart RAM address: byte}; (V2) Akuma's in 160B, akuma_rows"""
    (img, msk, fl, row), bank, cs = pose
    rd = lambda a: get(bank, a)          # (image and mask: both FT_SRCB, the pose's bank)
    pair = 0
    if msk:
        pair = 1 + ((fl & 0x10) >> 4)    # (Akuma's 1, the hawk's 2)
    srows, w = rd(img), rd(img + 1)
    p1 = img + 2
    end = srows
    mrows, z14, ri = 0, 0, 0
    if pair:
        mrows = rd(msk)
        z14 = msk + 2
        end = max(srows, mrows)
    col = coloured((img, msk, fl, row), scene)
    ak = akuma((img, msk, fl, row), scene) and akuma_rows(rd, img, msk, fl, row)
    wb = 2 * w if col else w
    end = row + end
    out, k = {}, 0

    def pair_next():
        nonlocal p1, z14, ri
        if ri < srows:
            p1 += w
        if ri < mrows:
            z14 += w
        ri += 1

    r = row
    while r < end and r <= BAND_ZEND:
        if r < FB_TOP:
            r += 1
            if pair:
                pair_next()
            else:
                p1 += w
            continue
        z = next(i for i, (a, b) in enumerate(F.ZONES) if a <= r <= b)
        z0, z1 = F.ZONES[z]
        h = z1 - z0 + 1
        fl0 = r - z0
        fn = min(z0 + h, end) - r
        t, c = cs[k]
        k += 1
        for g in list(range(fl0)) + list(range(fl0 + fn, h)):      # (the cell's other lines: zeros)
            for j in range(wb):
                out[(t - g) * 256 + c + j] = 0
        for i in range(fn):
            page = t - fl0 - i
            if col:
                if ak:                            # (Akuma's: by the image's row)
                    vs = ak[r + i - row] if r + i - row < len(ak) else bytes(wb)
                else:
                    vs = row_160b(rd, p1, z14, w, ri < srows, ri < mrows, fl & 0x80)
                for j, v in enumerate(vs):
                    out[page * 256 + c + j] = v
                pair_next()
                continue
            for y in range(w - 1, -1, -1):
                if pair:
                    s = rd(p1 + y) if ri < srows else 0
                    m = rd(z14 + y) if ri < mrows else 0xFF
                    if fl & 0x80:
                        m, s = _mir(m), _mir(s)
                    tt = (m >> 1) & m & 0x55
                    tt |= tt << 1
                    mm = ((s >> 1) | s) & 0x55
                    mm |= mm << 1
                    a = ~(mm | tt) & 0xFF
                    if pair != 2:
                        v = (((s >> 1) & 0x55) | s | (a & 0xAA)) & 0xFF
                    else:
                        tt = (a & 0x55) | ((s >> 1) & s & 0x55)
                        v = (((s << 1) | s) & 0xAA) | tt
                elif fl & 0x20:                   # (a mask's row)
                    b = rd(p1 + y)
                    if fl & 0x80:
                        b = _mir(b)
                    v = ~((((b >> 1) & b & 0x55) << 1)) & 0xAA
                elif fl & 0x80:
                    v = _mir(rd(p1 + y))
                else:
                    v = rd(p1 + y)
                out[page * 256 + c + ((w - 1 - y) if fl & 0x80 else y)] = v & 0xFF
            if pair:
                pair_next()
            else:
                p1 += w
        r += fn
    return out


# (V2) a hawk pixel's 160B (colour, palette in the group): the sprite's skin,
# black (the mask's clear where the sprite has none), white in P4 (0); its
# grey in P6 (2, colour 1: the band's grey, ColTail); the mask's kept
# pixels transparent
HAWK_160B = {1: (1, 0), 2: (1, 2), 3: (3, 0), "K": (2, 0)}


def row_160b(rd, p1, z14, w, srow, mrow, mir):
    """one row of a hawk pair as 160B: 2w bytes, left to right as shown
    (mirrored: the row's pixels reversed), as FtRowPH's classes but with
    the skin kept"""
    px = []
    for y in range(w):
        s = rd(p1 + y) if srow else 0
        m = rd(z14 + y) if mrow else 0xFF
        for q in range(4):
            sv, mv = (s >> (6 - 2 * q)) & 3, (m >> (6 - 2 * q)) & 3
            px.append(HAWK_160B[sv] if sv else (None if mv == 3 else HAWK_160B["K"]))
    if mir:
        px.reverse()
    out = []
    for k in range(0, len(px), 2):
        b = 0
        for j, v in enumerate(px[k:k + 2]):
            if v:
                b |= v[0] << (6 - 2 * j) | v[1] << (2 - 2 * j)
        out.append(b)
    return out



# (V2) Akuma's 160B (FINDINGS "Akuma's red", the user's option E: red cuffs
# and collar, the robe edged dark red): (colour, palette in the group): P4
# (0) skin, black, white; P7 (3, the guard's: FtColours, type 7) grey, the
# robe's edge (colour 2) and the cuffs' red (colour 3)
AK_160B = {1: (1, 0), "K": (2, 0), 3: (3, 0), 2: (1, 3), "E": (2, 3), "R": (3, 3)}
AK_WAIST = 106                  # (the robe from this screen row; above it the gi)
AK_LYING = 118                  # (poses from this row: on the floor, no robe edge)


def akuma_rows(rd, img, msk, fl, row):
    """a pose of Akuma's as 160B rows (2w bytes each, left to right as shown):
    the sprite's pixels (1 skin, 2 grey, 3 white) and a pair's black (its
    mask's clear where the sprite has none); white above the waist next to
    skin or grey (a cuff, the collar) red; skin from the waist down next to
    black or nothing (the robe's edge) dark red"""
    srows, w = rd(img), rd(img + 1)
    mrows = rd(msk) if msk else 0
    px = {}
    for r in range(max(srows, mrows)):
        for y in range(w):
            s = rd(img + 2 + r * w + y) if r < srows else 0
            m = rd(msk + 2 + r * w + y) if (msk and r < mrows) else 0xFF
            for q in range(4):
                sv, mv = (s >> (6 - 2 * q)) & 3, (m >> (6 - 2 * q)) & 3
                x = y * 4 + q
                if fl & 0x80:
                    x = w * 4 - 1 - x
                if sv:
                    px[(x, r)] = sv
                elif mv != 3:
                    px[(x, r)] = "K"
    cl = dict(px)
    for (x, r), v in px.items():
        if v == 3 and row + r < AK_WAIST and any(
                px.get((x + dx, r + dy)) in (1, 2) for dx, dy in ((1, 0), (-1, 0), (2, 0), (-2, 0), (0, -1))):
            cl[(x, r)] = "R"
        elif v == 1 and AK_WAIST <= row + r and row < AK_LYING and any(
                px.get((x + dx, r + dy), "K") == "K" for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            cl[(x, r)] = "E"
    out = []
    for r in range(max(srows, mrows)):
        b = bytearray(2 * w)
        for x in range(4 * w):
            v = cl.get((x, r))
            if v is not None:
                c, p = AK_160B[v]
                j = x & 1
                b[x >> 1] |= c << (6 - 2 * j) | p << (2 - 2 * j)
        out.append(bytes(b))
    return out
