"""Level 1 without the blitter, phase 0 (FINDINGS "Level 1 without the
blitter: the draws as pieces"): replays p7800-l1cap.lua's log.

    python probes/l1model.py work/analysis/l1cap/l1cap.log [--bitmap]

--bitmap: model 1, the blitter's own semantics on a model framebuffer
(rows 65-145), checked against both real buffers at every picture: proves
the log and the draw rules. A picture's mismatch is reported and the model
resynced from the real buffers."""
import sys
from collections import Counter

R0, R1 = 65, 146
NR = R1 - R0


def parse_dump(h):
    d = bytes.fromhex(h)
    return [bytearray(d[40 * r:40 * r + 40]) for r in range(NR)]


def px_get(row, x):
    return (row[x >> 2] >> (6 - 2 * (x & 3))) & 3


def px_set(row, x, v):
    s = 6 - 2 * (x & 3)
    row[x >> 2] = (row[x >> 2] & ~(3 << s) & 0xFF) | (v << s)


class Img:
    def __init__(self, data):
        self.rows, self.w = data[0], data[1]
        self.d = data[2:]

    def px(self, r, x, mir=False):
        """pixel x (0..4w-1) of image row r"""
        if mir:
            x = 4 * self.w - 1 - x
        return (self.d[r * self.w + (x >> 2)] >> (6 - 2 * (x & 3))) & 3


def signed(c):
    return c - 256 if c >= 128 else c


def blit(fb, img, kind, mode, col, row, sh, mirtab=None):
    col = signed(col)
    mir = kind in ("M", "MR")
    if kind in ("AR", "MR"):
        col = col - img.w + 1
    x0 = 4 * col + (sh >> 1)
    if mir:
        x0 = 4 * col + (sh >> 1)
    for r in range(img.rows):
        y = row + r
        if y >= 256:
            continue
        if not (R0 <= y < R1):
            continue
        dst = fb[y - R0]
        for k in range(4 * img.w):
            x = x0 + k
            if not (0 <= x < 160):
                continue
            v = img.px(r, k, mir)
            if mode == 0x00:
                v |= px_get(dst, x)
            elif mode >= 0x80:
                v &= px_get(dst, x)
            px_set(dst, x, v)


def fill(fb, kind, c0, w, top, n, v02, v12):
    rows = list(range(top, top + n))
    for i, y in enumerate(rows):
        if not (R0 <= y < R1):
            continue
        if kind == "rect":
            v = v02
        else:
            v = v02 if (n - 1 - i) % 2 == 0 else v12
        for c in range(c0, c0 + w):
            if 0 <= c < 40:
                fb[y - R0][c] = v


def main():
    path = sys.argv[1]
    imgs = {}
    fbs = None
    stats = Counter()
    bad_shown = 0
    for line in open(path):
        p = line.split()
        t = p[0]
        if t == "I":
            imgs[int(p[1], 16)] = Img(bytes.fromhex(p[3]))
        elif t == "P":
            n, drawn = int(p[1]), p[2]
            real = {"A": parse_dump(p[5]), "B": parse_dump(p[7])}
            if fbs is not None:
                for bname in "AB":
                    diffs = [(r + R0, c) for r in range(NR) for c in range(40) if fbs[bname][r][c] != real[bname][r][c]]
                    stats["pics", bname] += 1
                    if diffs:
                        stats["bad", bname] += 1
                        if bad_shown < 25:
                            bad_shown += 1
                            rs = sorted(set(r for r, c in diffs))
                            print("pic %d buf %s (drawn %s): %d bytes differ, rows %d-%d, cols %s" % (
                                n, bname, drawn, len(diffs), rs[0], rs[-1], sorted(set(c for r, c in diffs))[:20]))
            fbs = real
        elif fbs is None:
            continue
        elif t == "B":
            buf, kind, mode, col, row, sh, src = p[1], p[2], int(p[3], 16), int(p[4]), int(p[5]), int(p[6]), int(p[7], 16)
            blit(fbs[buf], imgs[src], kind, mode, col, row, sh)
        elif t == "F":
            buf, kind = p[1], p[2]
            c0, c1, bot, top, v02, v12, nofill = int(p[3]), int(p[4]), int(p[5]), int(p[6]), int(p[8], 16), int(p[9], 16), int(p[10])
            # the clip ($2DA4, bank 15's $F7A4): a top above row 0 (its raw
            # $06 under $23: here wrapped) is row 0; a left edge past 39
            # (negative) is 0 unless the right is past 40 too (nothing)
            if top >= 0xDD:             # (raw $06 under $23)
                top = 0
            if c0 >= 40:
                c0 = None if c1 >= 41 else 0
            elif c1 >= 41:
                c1 = 40
            if not nofill and c0 is not None:
                fill(fbs[buf], kind, c0, c1 - c0, top, bot - top, v02, v12)
        elif t == "L":
            buf, src, col, row, sh, lim, bank, entry, z52 = p[1], int(p[2], 16), int(p[3]), int(p[4]), int(p[5]), int(p[6]), int(p[7]), p[8], int(p[9])
            if src < 0xA000:
                continue
            if entry == "68" and (z52 >= 0x80 or z52 < 0x14):
                continue
            r = row
            while True:
                r += 2
                blit(fbs[buf], imgs[src], "A", 0x01, col, r, sh)
                if r >= lim:
                    break
        elif t == "C":
            for r in fbs[p[1]]:
                r[:] = bytes(40)
        elif t == "K":
            dst = p[1]
            src = "B" if dst == "A" else "A"
            fbs[dst] = [bytearray(r) for r in fbs[src]]
    print(dict(stats))


if __name__ == "__main__":
    main()
