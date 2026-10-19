"""Level 1 without the blitter: the pieces' data (FINDINGS "Level 1 without
the blitter: the data"). From p7800-l1cap.lua logs: every shape the level
draws below row 65 -- a blit (image, plain or mirrored, row), a column stack
(the column routine's: image, first row, limit), a fill that isn't the
row's background (pattern, rows) -- cut into windows of each zone it
crosses (the zone's lines x its bytes, line g of zone z at the line's own
page), its pixels converted for the zone's background: over the sky (rows
65-68) colour 2 transparent and black as 2 (palette 2); over black (69-117)
as they are (palette 1); over the floor (118-145) colour 1 transparent and
black as 1 (palette 3). Identical windows once. Sizes, and a packing into
cart RAM pages.

    python probes/l1shapes.py LOG [LOG ...]"""
import os
import sys
from collections import Counter, OrderedDict
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import l1model as L

# level 1's zones over rows 65-145 (as the builder makes them, the first
# split at the sky's end): (first row, lines)
ZONES = [(65, 4), (69, 4), (73, 5), (78, 1), (79, 2), (81, 8), (89, 1), (90, 2), (92, 8), (100, 8), (108, 8),
         (116, 1), (117, 1), (118, 1), (119, 8), (127, 6), (133, 2), (135, 10), (145, 1)]
SKY, BLACK, FLOOR = 2, 0, 1


def row_bg(r):
    return SKY if r < 69 else (BLACK if r < 118 else FLOOR)


def conv(v, bg):
    """a pixel over the row's background: 0 transparent"""
    if v == bg:
        return 0
    if v == 0:
        return bg               # black where the background colour's index was
    return v


def shapes_from(paths):
    imgs, shapes = {}, OrderedDict()
    for path in paths:
        for line in open(path):
            p = line.split()
            if p[0] == "I":
                imgs[int(p[1], 16)] = L.Img(bytes.fromhex(p[3]))
            elif p[0] == "B":
                src, kind, row = int(p[7], 16), p[2], int(p[5])
                if src in (0xAA11, 0xAA31):
                    continue
                mir = kind in ("M", "MR")
                shapes.setdefault(("B", src, mir, row, int(p[3], 16)), 0)
                shapes[("B", src, mir, row, int(p[3], 16))] += 1
            elif p[0] == "L":
                src, row, lim, entry, z52 = int(p[2], 16), int(p[4]), int(p[6]), p[8], int(p[9])
                if src < 0xA000:
                    continue
                mir = entry == "68" and (z52 >= 0x80 or z52 < 0x14)
                shapes.setdefault(("L", src, mir, row, lim), 0)
                shapes[("L", src, mir, row, lim)] += 1
            elif p[0] == "F":
                kind, c0, c1, bot, top, v02, v12, nf = p[2], int(p[3]), int(p[4]), int(p[5]), int(p[6]), \
                    int(p[8], 16), int(p[9], 16), int(p[10])
                if nf:
                    continue
                if top >= 0xDD:
                    top = 0
                key = ("F", kind, max(top, 65), min(bot, 146), v02, v12 if kind == "pat" else v02, (bot - top) % 2)
                if key[2] >= key[3]:
                    continue
                shapes.setdefault(key, 0)
                shapes[key] += 1
    return imgs, shapes


def rows_of(shape, imgs):
    """{screen row: list of 2-bit pixels, 4 a byte} of the shape, and its width in bytes"""
    out = {}
    if shape[0] in ("B", "L"):
        _, src, mir, row, last = shape
        img = imgs[src]
        tops = [row] if shape[0] == "B" else list(range(row, last + 1, 2)) + ([last] if (last - row) % 2 else [])
        if shape[0] == "L":
            r = row
            tops = [r]
            while True:
                r += 2
                tops.append(r)
                if r >= last:
                    break
        for t in tops:
            for r in range(img.rows):
                out[t + r] = [img.px(r, k, mir) for k in range(4 * img.w)]
        return out, img.w
    _, kind, top, bot, v02, v12, odd = shape
    n = bot - top
    for i in range(n):
        v = v02 if (kind == "rect" or (n - 1 - i) % 2 == 0) else v12
        out[top + i] = [(v >> (6 - 2 * (k & 3))) & 3 for k in range(4 * 32)]
    return out, 32


def windows(shape, imgs):
    """[(zone, bytes: lines x w)] the shape's windows"""
    rows, w = rows_of(shape, imgs)
    out = []
    for zi, (z0, h) in enumerate(ZONES):
        if not any(z0 <= r < z0 + h for r in rows):
            continue
        data = bytearray()
        for r in range(z0, z0 + h):
            px = rows.get(r)
            for k in range(w):
                b = 0
                if px:
                    for q in range(4):
                        b |= conv(px[4 * k + q], row_bg(r)) << (6 - 2 * q)
                data.append(b)
        out.append((zi, bytes(data)))
    return out


def main():
    imgs, shapes = shapes_from(sys.argv[1:])
    print("shapes:", len(shapes), Counter(k[0] for k in shapes))
    wins = {}
    raw = 0
    for s in shapes:
        if s[0] == "F" and "--fills" not in sys.argv:
            continue                # (fills: characters, a few bytes each)
        for zi, data in windows(s, imgs):
            raw += len(data)
            wins.setdefault((ZONES[zi][1], data), []).append((s, zi))
    tot = sum(len(d) for h, d in wins)
    print("windows: %d (%d bytes), before sharing %d bytes" % (len(wins), tot, raw))
    blank = sum(len(d) for h, d in wins if not any(d))
    print("all-transparent windows: %d bytes" % blank)
    # packing: 27 pages ($58-$72), bytes 16-255 of each: a window of h lines
    # at h consecutive pages, the same low byte
    pages = {p: [0] * 256 for p in range(0x58, 0x73)}
    for p in pages:
        for c in range(16):
            pages[p][c] = 1
    def fit(h, w):
        for top in range(0x72, 0x58 + h - 2, -1):
            for c in range(16, 257 - w):
                if all(not pages[top - g][c + k] for g in range(h) for k in range(w)):
                    for g in range(h):
                        for k in range(w):
                            pages[top - g][c + k] = 1
                    return top, c
        return None
    failed = 0
    for (h, data) in sorted(wins, key=lambda k: (-k[0], -len(k[1]))):
        if not any(data):
            continue
        if fit(h, len(data) // h) is None:
            failed += len(data)
    used = sum(sum(v) - 16 for v in pages.values())
    print("packed into $58-$72: %d bytes used, %d bytes didn't fit" % (used, failed))
    big = Counter()
    for s, n in shapes.items():
        if s[0] == "F" and "--fills" not in sys.argv:
            continue
        big[s] = sum(len(d) for zi, d in windows(s, imgs))
    print("largest shapes:", [("%s %s" % (s[0], "%04X" % s[1] if s[0] != "F" else s[1:]), b) for s, b in big.most_common(12)])


if __name__ == "__main__":
    main()
