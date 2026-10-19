"""The fighters' lower bodies as the cartridge holds them (FINDINGS "The
fighters as objects: step 2"), decoded from the built .a78 (the blobs in the
art bank, found through bank 5's FT_LOWLO/FT_LOWHI) and drawn slice by slice
in each slice's palette, beside the original's composition (the mask
clearing to black, the sprite ORed over it; its belt the background). A violet background shows what
is transparent; the grid's zone lines are marked.

    python probes/fighterconv.py out.png"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import fighters7800 as F   # noqa: E402
import layout7800 as L     # noqa: E402

from PIL import Image, ImageDraw   # noqa: E402

ROOT = os.path.join(HERE, "..")
GAME = {0: None, 1: (232, 144, 115), 2: (136, 136, 136), 3: (238, 238, 238)}
BLK = {0: None, 1: (232, 144, 115), 2: (0, 0, 0), 3: (238, 238, 238)}
ORIG = {F.BLACK: (0, 0, 0), 1: (232, 144, 115), 2: (136, 136, 136), 3: (238, 238, 238)}
BG = (90, 60, 160)


def main():
    rom = open(os.path.join(ROOT, "work", "karateka7800.a78"), "rb").read()[128:]
    sym = {}
    for line in open(os.path.join(ROOT, "work", "karateka7800.sym")):
        t = line.split()
        if len(t) == 2:
            sym[t[1]] = int(t[0], 16)

    def bank_get(b):
        return lambda a: rom[b * 0x4000 + a - 0x8000]
    top, art = bank_get(L.TOP_BANK), bank_get(L.ART_BANK)
    fart = F.Art()
    S, cells = 3, []
    for x in range(42):
        at = top(sym["FT_LOWLO"] + x) | top(sym["FT_LOWHI"] + x) << 8
        width, slices = F.unblob(art, at)
        orig, _ = F.lower_pixels(fart, x, belt=False)
        xs = [p[0] for p in orig]
        ys = [p[1] for p in orig]
        x0, y0 = min(xs) // 4 * 4, min(ys)
        w, h = max(xs) + 1 - x0, max(ys) + 1 - y0
        a = Image.new("RGB", (w, h), BG)
        for (px, py), v in orig.items():
            a.putpixel((px - x0, py - y0), ORIG[v])
        b = Image.new("RGB", (w, h), BG)
        for z, r0, n, b0, sw, pal, data in slices:
            pal_c = BLK if pal else GAME
            for r in range(n):
                for bb in range(sw):
                    byte = data[r * sw + bb]
                    for k in range(4):
                        v = (byte >> (6 - 2 * k)) & 3
                        if pal_c[v]:
                            b.putpixel(((b0 + bb) * 4 + k - x0, F.ZONES[z][0] + r0 + r - y0), pal_c[v])
        cell = Image.new("RGB", (w * 2 + 3, h), (255, 255, 255))
        cell.paste(a, (0, 0))
        cell.paste(b, (w + 3, 0))
        dr = ImageDraw.Draw(cell)
        for z0, z1 in F.ZONES:                       # the grid's zone tops, on the converted side
            if y0 < z0 < y0 + h:
                dr.line([(w + 3, z0 - y0), (w * 2 + 2, z0 - y0)], fill=(255, 255, 0))
        cells.append(cell.resize((cell.width * S, cell.height * S), Image.NEAREST))
    per = 7
    rows = [cells[i:i + per] for i in range(0, len(cells), per)]
    W = max(sum(c.width + 12 for c in r) for r in rows)
    H = sum(max(c.height for c in r) + 12 for r in rows)
    out = Image.new("RGB", (W, H), (255, 255, 255))
    y = 0
    for r in rows:
        x = 0
        for c in r:
            out.paste(c, (x, y))
            x += c.width + 12
        y += max(c.height for c in r) + 12
    out.save(sys.argv[1])
    print("42 poses drawn to", sys.argv[1])


if __name__ == "__main__":
    main()
