"""Level 2 without the blitter, the model (FINDINGS "Levels 2-4 without the
blitter"): objects over a fixed background, as level 1's rules make them,
against the game's own buffers in p7800-l1cap.lua logs.

Each buffer: its instances in drawing order (a blit adds one, or moves it to
the end if the same image, kind, mode, row and place is there; when the
picture's view V changed, those not drawn in it are out: the game draws
again all it shows when the view moves); a fill (not a fighter-box erase)
takes out each one whose middle it covers; a clear empties it; a copy copies
the other's. A picture: the background (rows 65-117 black, 118-145 the
floor's stripes: $55 on odd rows), then the instances (a store opaque over
its rectangle, an OR's non-zero pixels, an AND mask ANDed in).

    python probes/l2model.py SCENE LOG:STATE.BIN [--show N --png OUT]"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from l1worldlist import state_mode, signed      # noqa: E402

R0, R1 = 65, 146
FLOOR0 = 118


def bg(r):
    return 0x55 if r >= FLOOR0 and r % 2 == 1 else 0x00


class Img(object):
    def __init__(self, hexs):
        d = bytes.fromhex(hexs)
        self.rows, self.w, self.d = d[0], d[1], d[2:]

    def px(self, r, x, mir):
        if mir:
            x = 4 * self.w - 1 - x
        b = self.d[r * self.w + (x >> 2)]
        return (b >> (6 - 2 * (x & 3))) & 3


def run(scene, log, st, show=None, png=None):
    modes = state_mode(st)
    imgs = {}
    bufs = {"A": [], "B": []}
    drawn = {"A": set(), "B": set()}
    view = {"A": None, "B": None}
    pend, out = [], []
    for line in open(log):
        p = line.split()
        if p[0] == "I":
            imgs[(int(p[1], 16), int(p[2]))] = Img(p[3])
            continue
        if p[0] != "P":
            pend.append(p)
            continue
        n, dr = int(p[1]), p[2]
        z = bytes.fromhex(p[3])
        V = 4 * z[0] + z[1] // 2
        for q in pend:
            k = q[0]
            if k == "C":
                bufs[q[1]] = []
            elif k == "K":
                dst = q[1]
                bufs[dst] = list(bufs["B" if dst == "A" else "A"])
            elif k == "B":
                src, bk = int(q[7], 16), int(q[8])
                im = imgs.get((src, bk)) or next(v for kk, v in imgs.items() if kk[0] == src)
                col = signed(int(q[4]))
                if q[2] in ("AR", "MR"):
                    col -= im.w - 1
                x = 4 * col + (int(q[6]) >> 1)
                key = (src, bk, q[2] in ("M", "MR"), int(q[5]), int(q[3], 16), x)
                b = bufs[q[1]]
                if key in b:
                    b.remove(key)
                b.append(key)
                drawn[q[1]].add(key)
            elif k == "F" and q[10] == "0":
                c0, c1, bot, top = int(q[3]), int(q[4]), int(q[5]), int(q[6])
                if top >= 0xDD:
                    top = 0
                if c0 >= 40:
                    if c1 >= 41:
                        continue
                    c0 = 0
                c1 = min(c1, 40)
                keep = []
                for key in bufs[q[1]]:
                    im = imgs.get(key[:2]) or next(v for kk, v in imgs.items() if kk[0] == key[0])
                    mr, mc = key[3] + im.rows // 2, key[5] + 2 * im.w
                    if top <= mr < bot and 4 * c0 <= mc < 4 * c1:
                        continue
                    keep.append(key)
                bufs[q[1]] = keep
        pend = []
        # the picture done: its view; a new one drops what wasn't drawn again
        if view[dr] is not None and view[dr] != V:
            bufs[dr] = [k for k in bufs[dr] if k in drawn[dr]]
        view[dr] = V
        drawn[dr] = set()
        if modes.get(n, (0, 0, 0))[1] != scene:
            continue
        pic = [[(bg(R0 + r) >> (6 - 2 * (c & 3))) & 3 for c in range(160)] for r in range(R1 - R0)]
        for src, bk, mir, row, mode, x in bufs[dr]:
            im = imgs.get((src, bk)) or next(v for kk, v in imgs.items() if kk[0] == src)
            for rr in range(im.rows):
                r = row + rr
                if not R0 <= r < R1:
                    continue
                for xx in range(4 * im.w):
                    sx = x + xx
                    if not 0 <= sx < 160:
                        continue
                    v = im.px(rr, xx, mir)
                    if mode >= 0x80:
                        pic[r - R0][sx] &= v
                    elif mode == 0:
                        pic[r - R0][sx] |= v
                    else:
                        pic[r - R0][sx] = v
        real = bytes.fromhex(p[5] if dr == "A" else p[7])
        diff = 0
        for r in range(R1 - R0):
            for c in range(160):
                if (real[r * 40 + (c >> 2)] >> (6 - 2 * (c & 3))) & 3 != pic[r][c]:
                    diff += 1
        out.append((n, diff, len(bufs[dr])))
        if png and show == n:
            from PIL import Image
            PAL = [(0, 0, 0), (230, 150, 120), (110, 160, 240), (240, 240, 240)]
            im = Image.new("RGB", (160, 2 * (R1 - R0) + 4), (255, 0, 255))
            for r in range(R1 - R0):
                for c in range(160):
                    im.putpixel((c, r), PAL[pic[r][c]])
                    im.putpixel((c, R1 - R0 + 4 + r), PAL[(real[r * 40 + (c >> 2)] >> (6 - 2 * (c & 3))) & 3])
            im.resize((640, im.height * 4), Image.NEAREST).save(png)
    return out


def main():
    scene = int(sys.argv[1])
    show = int(sys.argv[sys.argv.index("--show") + 1]) if "--show" in sys.argv else None
    png = sys.argv[sys.argv.index("--png") + 1] if "--png" in sys.argv else None
    for arg in sys.argv[2:]:
        if ":" not in arg or arg.startswith("--") or arg == png:
            continue
        log, st = arg.rsplit(":", 1)
        res = run(scene, log, st, show, png)
        bad = [r for r in res if r[1]]
        print("%s: %d pictures, %d differ; most instances %d" % (log, len(res), len(bad), max(r[2] for r in res)))
        print("   pixels/100:", dict(sorted(Counter(min(r[1] // 100, 10) for r in bad).items())))
        print("   first:", bad[:15])


if __name__ == "__main__":
    main()
