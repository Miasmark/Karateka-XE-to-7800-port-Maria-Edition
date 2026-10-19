"""Render images (rows, width, then rows x width bytes of 2-bit pixels, as
the blitter draws them) side by side into one PNG, each under a number, to
look at: python probes/drawimages.py out.png FILE.csv  (a csv with columns
rows, width and cart = "bank:$offset ..." (the first is drawn)), or pass
bank:offset pairs. Colours: 0 black, 1 orange, 2 blue, 3 white."""
import csv
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import link7800 as K      # noqa: E402

body = open(K.CAR, "rb").read()[16:]
SCALE = int(os.environ.get("SCALE", "1"))
PAL = [(0, 0, 0), (230, 120, 70), (90, 110, 255), (255, 255, 255)]
DIGITS = {  # 3x5
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
    "4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001001001001",
    "8": "111101111101111", "9": "111101111001111"}


def png(path, img):
    h, w = len(img), len(img[0])
    raw = b"".join(b"\x00" + bytes(v for px in r for v in px) for r in img)
    def ch(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + ch(b"IDAT", zlib.compress(raw)) + ch(b"IEND", b""))


def image(bank, off):
    rows, width = body[bank * 0x2000 + off], body[bank * 0x2000 + off + 1]
    d = body[bank * 0x2000 + off + 2:bank * 0x2000 + off + 2 + rows * width]
    return [[PAL[(d[r * width + c] >> s) & 3] for c in range(width) for s in (6, 4, 2, 0) for _ in range(2 * SCALE)]
            for r in range(rows) for _ in range(SCALE)]


def main():
    out = sys.argv[1]
    items = []
    if sys.argv[2].endswith(".csv"):
        for r in csv.DictReader(open(sys.argv[2])):
            b, o = r["cart"].split()[0].split(":")
            items.append((int(b), int(o[1:], 16)))
    else:
        for x in sys.argv[2:]:
            b, o = x.split(":")
            items.append((int(b), int(o.lstrip("$"), 16)))
    tiles = [image(b, o) for b, o in items]
    cols = 8
    cw = max(len(t[0]) for t in tiles) + 6
    rh = max(len(t) for t in tiles) + 12
    W = cols * cw
    H = ((len(tiles) + cols - 1) // cols) * rh
    img = [[(40, 20, 20)] * W for _ in range(H)]
    for k, t in enumerate(tiles):
        ox, oy = (k % cols) * cw + 3, (k // cols) * rh + 9
        for y, row in enumerate(t):
            for x, px in enumerate(row):
                img[oy + y][ox + x] = px
        for j, ch in enumerate(str(k)):
            for i, bit in enumerate(DIGITS[ch]):
                if bit == "1":
                    img[oy - 8 + i // 3][ox + j * 4 + i % 3] = (255, 255, 0)
    png(out, img)
    print("%d images" % len(tiles))


if __name__ == "__main__":
    main()
