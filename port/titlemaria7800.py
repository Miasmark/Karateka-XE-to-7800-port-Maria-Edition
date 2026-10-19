"""The title, the opening story and the ending's text as MARIA data in banks
0's and 4's MARIA halves (FINDINGS "The title and the opening scroll in bank
0's MARIA copy", "The ending's text as characters").

Bank 0 (scenes 0 and 4's page) is the only window bank while the title and
the story are up, so its MARIA copy can hold data the other banks' copies
don't: the pages of the top data's groups that hold only levels 1-3's sets
(layout7800 TS_PAGES), which bank 0 is never in for.

- **The story** in character mode: the game's 22 strings rendered as its
  text routine ($0780) draws them, 14 rows apart, cut into characters 4
  pixels wide and 14 rows tall (one string a slot), the blank one code 0.
  Character k's row r at page TS_CB + 13 - r, column k (a zone ending on
  slot row e reads its rows with CHBASE TS_CB + 14 - e). Each string's 40
  codes, its map.
- **The ending's text** (scene 4, bank 4: its ten strings, $6318/$6323,
  14 rows apart from row 0) the same way in bank 4's copy, its characters
  and maps where the story's are in bank 0's (the far code and its tables
  are the same in both pages).
- **The title**: its ten objects (the logo's letters, the copyright lines:
  build7800's table) drawn as MARIA would draw them (a later object's
  non-zero pixels over the earlier's) into two canvases 40 bytes wide (the
  logo's rows and the copyright's), each cut into chunks of at most 16 rows:
  a chunk's first row at page TS_TOP, each row one page lower, its own 40
  columns.
"""
import dis as D

GLYPH_LO, GLYPH_HI, ADV_COL, ADV_SHIFT, GLYPH_BASE = 0x06F4, 0x0714, 0x0734, 0x0754, 0x0480
STORY_LO, STORY_HI, FIRST, LAST, PITCH = 0x7BCC, 0x7BE6, 4, 25, 14


def render_string(m, img, at, top, width=40):
    """OR the string at `at` into img (bytearrays `width` long), its glyphs'
    top at row `top`: as $0780 places them (probes/storytext.py, checked
    byte for byte against the original's framebuffers)"""
    col, shift = m[at], m[at + 1]
    i = at + 2
    while m[i] >= 0x60:
        x = m[i] - 0x60
        if x:
            p = GLYPH_BASE + (m[GLYPH_HI + x] << 8 | m[GLYPH_LO + x])
            rows, w = m[p], m[p + 1]
            px = shift >> 1
            for r in range(rows):
                if not 0 <= top + r < len(img):
                    continue
                v = 0
                for b in range(w):
                    v = v << 8 | m[p + 2 + r * w + b]
                v = (v << 8) >> (2 * px)
                for b in range(w + 1):
                    c = col + b
                    if 0 <= c < width:
                        img[top + r][c] |= (v >> (8 * (w - b))) & 0xFF
        col += m[ADV_COL + x]
        shift += m[ADV_SHIFT + x]
        if shift >= 8:
            col += 1
            shift -= 8
        i += 1


def story_image(m, strings=None):
    """the strings (addresses; the story's by default) PITCH rows apart"""
    if strings is None:
        strings = [m[STORY_HI + k] << 8 | m[STORY_LO + k] for k in range(FIRST, LAST + 1)]
    img = [bytearray(40) for _ in range(len(strings) * PITCH)]
    for k, at in enumerate(strings):
        render_string(m, img, at, k * PITCH)
    return img


END_LO, END_HI, END_N = 0x6318, 0x6323, 10
MAP_COL = 160                 # the maps' columns in the top 16 pages (the title's chunks before)


def ending_strings(m4):
    return [m4[END_HI + k] << 8 | m4[END_LO + k] for k in range(END_N)]


def story_chars(img):
    """(characters: each its 14 rows; maps: each string's 40 codes)"""
    chars, code = [bytes(PITCH)], {bytes(PITCH): 0}
    maps = []
    for s in range(len(img) // PITCH):
        line = []
        for c in range(40):
            t = bytes(img[s * PITCH + r][c] for r in range(PITCH))
            if t not in code:
                code[t] = len(chars)
                chars.append(t)
            line.append(code[t])
        maps.append(line)
    if len(chars) > 256:
        raise SystemExit("the story: %d characters, more than 256 codes" % len(chars))
    return chars, maps


def title_canvases(m, tobj):
    """{canvas: (its first buffer row, rows of 40 bytes)}: the objects (source,
    column, top line, shift, canvas) drawn at x = 4 x column + shift / 2,
    row = top line - 35, a later object's non-zero pixels over the earlier's"""
    px = {0: {}, 1: {}}
    for isrc, col, line, shift, can in tobj:
        rows, w = m[isrc], m[isrc + 1]
        x0, y0 = 4 * col + shift // 2, line - 35
        for r in range(rows):
            for b in range(w):
                v = m[isrc + 2 + r * w + b]
                for k in range(4):
                    p = (v >> (6 - 2 * k)) & 3
                    if p and 0 <= x0 + 4 * b + k < 160:
                        px[can][(x0 + 4 * b + k, y0 + r)] = p
    out = {}
    for can, p in px.items():
        r0, r1 = min(y for x, y in p), max(y for x, y in p)
        rows = []
        for y in range(r0, r1 + 1):
            row = bytearray(40)
            for x in range(160):
                row[x // 4] |= p.get((x, y), 0) << (6 - 2 * (x % 4))
            rows.append(bytes(row))
        out[can] = (r0, rows)
    return out


TAKEN = set()                   # (the last layout's addresses)


def layout(window, pages, tobj, scene=0):
    """the text's characters and maps (scene 0: the story's, and the title's
    chunks; scene 4: the ending's) written into `window` (MARIA's $8000-$BFFF
    block for its page's bank) in `pages` (the TS pages, low to high):
    (equates, tables as assembler lines, a summary)"""
    m = D.memory(scene)
    chars, maps = story_chars(story_image(m, ending_strings(m) if scene == 4 else None))
    p0, p1 = pages[0], pages[-1]
    cb = p0                                   # the characters: 14 pages from the lowest
    if cb + PITCH - 1 >= p1 - 15:
        raise SystemExit("the story's characters and the title's 16 pages overlap")

    TAKEN.clear()               # (each byte this layout writes, zeros too: V2's level windows go around them)

    def put(page, col, data):
        a = (page - 0x80) * 256 + col
        if any(window[a:a + len(data)]):
            raise SystemExit("bank 0's MARIA data overlaps at $%02X%02X" % (page, col))
        window[a:a + len(data)] = data
        TAKEN.update(page * 256 + col + k for k in range(len(data)))

    for k, t in enumerate(chars):
        for r in range(PITCH):
            put(cb + PITCH - 1 - r, k, bytes([t[r]]))
    top = p1                                  # the title's chunks and the maps: the top 16 pages
    chunks, col = [], 0
    for can, (r0, rows) in sorted(title_canvases(m, tobj).items() if scene == 0 else []):
        for k in range(0, len(rows), 16):
            part = rows[k:k + 16]
            for i, row in enumerate(part):
                put(top - i, col, row)
            chunks.append((r0 + k, len(part), top, col, can))
            col += 40
    if col > MAP_COL:
        raise SystemExit("the title's chunks reach the maps' columns")
    maplo, maphi = [], []
    for i, line in enumerate(maps):
        page, c = top - i // 2, MAP_COL + 40 * (i % 2)
        if page < top - 15 or c + 40 > 256:
            raise SystemExit("the story's maps don't fit beside the title's chunks")
        put(page, c, bytes(line))
        maplo.append(c)
        maphi.append(page)
    eq = {"TS_CB": cb, "TS_NCH": len(chunks)}
    by = lambda vs: ["    .byte " + ",".join("$%02X" % v for v in vs[i:i + 16]) for i in range(0, len(vs), 16)]
    tab = (["TS_MAPLO:"] + by(maplo) + ["TS_MAPHI:"] + by(maphi)
           + ["TS_TK0:"] + by([c[0] for c in chunks]) + ["TS_TKN:"] + by([c[1] for c in chunks])
           + ["TS_TKP:"] + by([c[2] for c in chunks]) + ["TS_TKC:"] + by([c[3] for c in chunks])
           + ["TS_TKM:"] + by([1 << c[4] for c in chunks]))
    info = "%d characters (%d bytes), %d maps%s" % (
        len(chars), len(chars) * PITCH, len(maps), "; the title in %d chunks" % len(chunks) if chunks else "")
    return eq, tab, info
