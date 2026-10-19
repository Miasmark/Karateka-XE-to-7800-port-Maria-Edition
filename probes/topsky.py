"""Check the top rows as MARIA objects over a sky-blue background against
the bitmap (probes/p7800-toplog.lua's log, image bytes from the original's
asset log). The bitmap: the room's sky fill, then each piece written whole
(colour 0 black included) in draw order, erase fills as logged. The objects:
the background is the sky (colour 2), each piece converted (its colour 2
transparent, its colour 0 black as an opaque colour), drawn in order.
Compared at every flip, for the buffer shown, rows 0 to CUT-1.
    python probes/topsky.py work/analysis/top1/toplog.log work/analysis/as-s1/assetlog.log [CUT]
"""
import sys

CUT = int(sys.argv[3]) if len(sys.argv) > 3 else 45
SKY, BLACK = 2, 4            # 4: the converted pieces' black (an opaque colour)


def images(path):
    out = {}
    for line in open(path):
        p = line.split()
        if p[0] == 'I':
            src = int(p[2], 16) + 0x4000          # the port's address (scene data $6xxx -> $Axxx)
            b = bytes.fromhex(p[5])
            out.setdefault(src, b)
    return out


def pixels(img):
    rows, width = img[0], img[1]
    return rows, width, [[(img[2 + r * width + c // 4] >> (6 - 2 * (c % 4))) & 3 for c in range(4 * width)]
                         for r in range(rows)]


def main():
    imgs = images(sys.argv[2])
    pieces = {'A': [], 'B': []}       # (x, top, src) in draw order, on top of the sky
    fills = {'A': [], 'B': []}        # what the bitmap's top holds besides: nothing, all sky
    pics = bad = 0
    first = []
    for line in open(sys.argv[1]):
        p = line.split()
        if p[0] == 'C':
            pieces[p[2]] = []
        elif p[0] == 'K':
            pieces[p[2]] = list(pieces['B' if p[2] == 'A' else 'A'])
        elif p[0] == 'B':
            b, src, x, top = p[2], int(p[4], 16), int(p[7]), int(p[8])
            pieces[b].append((x, top, src))
        elif p[0] == 'F':
            b, c0, c1, top, bot = p[2], int(p[4]), int(p[5]), int(p[6]), int(p[7])
            keep = []
            for (x, t, src) in pieces[b]:
                rows, width, _ = pixels(imgs[src])
                if 4 * c0 <= max(x, 0) and min(x + 4 * width - 1, 159) <= 4 * c1 - 1 and top <= t and min(t + rows - 1, CUT - 1) <= bot:
                    continue                      # erased (whole: probes/topana.py)
                keep.append((x, t, src))
            pieces[b] = keep
        elif p[0] == 'P':
            pics += 1
            shown = p[3]
            bmp = [[SKY] * 160 for _ in range(CUT)]
            obj = [[SKY] * 160 for _ in range(CUT)]
            for (x, t, src) in pieces[shown]:
                if src not in imgs:
                    continue
                rows, width, px = pixels(imgs[src])
                for r in range(rows):
                    y = t + r
                    if not 0 <= y < CUT:
                        continue
                    for c in range(4 * width):
                        X = (x + c) & 0xFF
                        if X >= 160:
                            continue
                        v = px[r][c]
                        bmp[y][X] = v                              # the blit: every pixel
                        if v != SKY:
                            obj[y][X] = BLACK if v == 0 else v     # the object: sky transparent
            for y in range(CUT):
                for X in range(160):
                    a = bmp[y][X]
                    o = obj[y][X]
                    if (0 if o == BLACK else o) != a:
                        bad += 1
                        if len(first) < 8:
                            first.append((pics, shown, y, X, a, o))
                        break
    missing = {src for b in pieces for (x, t, src) in pieces[b] if src not in imgs}
    print("%d pictures compared (rows 0-%d), %d rows differing%s" % (pics, CUT - 1, bad,
          "; images without bytes: %s" % sorted("%04X" % m for m in missing) if missing else ""))
    for f in first:
        print("   picture %d buffer %s row %d x %d: bitmap colour %d, objects %s" % f)


main()
