"""(V2) Mt Fuji redrawn (FINDINGS "Mt Fuji"): the mountain's top pieces (level
1 and the attract loop's $6948/$6976, level 2's $6592/$65B8) kept white as
the original, its black specks replaced by soft blue-grey gullies, its right
flank in a pale blue shade. The pieces take palette 5 (FUJI_PAL: white,
shade, gully), their sky (or window pane) colour transparent; TopColours
sets the palette at the top of each frame.

Each piece is drawn from its own silhouette in its own columns: every piece
is centred on the peak, its rows counted from the summit's (FUJI_TOP)."""
WHITE, SHADE, GULLY = 0x0E, 0x8C, 0x8A
FUJI_PAL = (WHITE, SHADE, GULLY)          # palette 5's colours 1-3
FUJI_TOP = 46                             # the summit's buffer row
SKY_C = 2                                 # the images' sky (or pane) colour
# the gullies: (slope in pixels a row from the peak, the first row, a dash
# pattern of four rows), fanning down from below the summit
GULLIES = [(-0.75, 7, (1, 1, 1, 0)), (-0.25, 10, (1, 1, 0, 1)), (0.35, 9, (1, 1, 1, 0)), (0.85, 8, (1, 0, 1, 1))]


def colour(y, x, a, b, peak, sky_inside):
    """palette 5's colour (0 none) of the piece's pixel x on mountain row y,
    its row's silhouette a-b"""
    if x < a or x > b or (sky_inside and y < 3):          # (the sky and the crater)
        return 0
    c = 1
    if y > 1 and x > peak + 1 + (y - 2) * 0.3:
        c = 2
    for slope, y0, dash in GULLIES:
        if y >= y0 and round(peak + slope * (y - y0 + 1)) == x and dash[(y - y0) % 4]:
            c = 3
    if c == 3 and x in (a, b):
        c = 1
    return c


def art(rows, w, byte_at, top):
    """the piece's new bytes (rows x w), from its image (byte_at(r, b)) drawn
    at buffer row top"""
    px = [[(byte_at(r, b) >> (6 - 2 * k)) & 3 for b in range(w) for k in range(4)] for r in range(rows)]
    peak = (w * 4 - 1) / 2
    out = []
    for r, row in enumerate(px):
        xs = [i for i, v in enumerate(row) if v != SKY_C]
        a, b = (min(xs), max(xs)) if xs else (99, -1)
        cols = [colour(top - FUJI_TOP + r, x, a, b, peak, row[x] == SKY_C) for x in range(w * 4)]
        out.append([sum(c << (6 - 2 * k) for k, c in enumerate(cols[4 * j:4 * j + 4])) for j in range(w)])
    return out
