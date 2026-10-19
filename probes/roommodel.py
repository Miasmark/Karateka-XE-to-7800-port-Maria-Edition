"""Levels 3 and 4 without the blitter, the model (FINDINGS "Levels 2-4
without the blitter"): replays p7800-l1cap.lua's log by the rules the 6502
will follow, as MARIA would draw it, and compares each picture of SCENE with
the game's own buffer (the P dumps, rows 65-145).

Each buffer keeps:
- the floor: a mask of the 40 byte columns whose rows 118-144 show the
  floor's stripes ($AA on even rows), set by a fill of the stripes there
  ($AA/$00 in the floor's phase) and cleared by a black rect over them;
- its instances in the game's drawing order: a blit adds one, or moves it
  to the end if it is already there (the same image, row, mode, mirror and
  place); a fill (not a fighter-box erase, S_NOFILL) takes out each one
  whose middle (row and column) it covers;
- a clear empties both; a copy copies the other's.
A picture is black, the floor's stripes, then the instances: a stored blit
opaque over its rectangle (its windows' clear colour is one it doesn't use),
an OR blit's non-zero pixels, an AND mask's 0 pixels as black.

    python probes/roommodel.py SCENE LOG:STATE.BIN [...] [--show N] [--png OUT]"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from l1worldlist import state_mode, signed      # noqa: E402

R0, R1 = 65, 146
SPILL_BG = "--spillblack" not in sys.argv     # (the spill's right pixels: the floor's stripe on its rows)
STORE_CANVAS = "--objstores" not in sys.argv   # (stores into the canvas, write-only)
FLOOR0, FLOOR1 = 118, 145


def stripes(r):
    return 0xAA if r % 2 == 0 else 0x00


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
    bufs = {"A": {"inst": [], "canvas": bytearray(40 * 81)}, "B": {"inst": [], "canvas": bytearray(40 * 81)}}
    pend = []
    out = []
    for line in open(log):
        p = line.split()
        t = p[0]
        if t == "I":
            imgs[int(p[1], 16)] = Img(p[3])
            continue
        if t != "P":
            pend.append(p)
            continue
        n, drawn = int(p[1]), p[2]
        # (the events before a picture are applied whatever its scene: the
        # buffers carry on)
        for q in pend:
            k = q[0]
            if k == "C":
                bufs[q[1]] = {"inst": [], "canvas": bytearray(40 * 81)}
            elif k == "K":
                dst = q[1]
                src = "B" if dst == "A" else "A"
                bufs[dst] = {"inst": list(bufs[src]["inst"]), "canvas": bytearray(bufs[src]["canvas"])}
            elif k == "B":
                b = bufs[q[1]]
                src = int(q[7], 16)
                im = imgs[src]
                col = signed(int(q[4]))
                if q[2] in ("AR", "MR"):
                    col -= im.w - 1
                x = 4 * col + (int(q[6]) >> 1)
                key = (src, q[2] in ("M", "MR"), int(q[5]), int(q[3], 16), x)
                # (an image is shown once: drawn again, wherever, it moves:
                # the rooms scroll by redrawing their walls further along)
                b["inst"] = [k2 for k2 in b["inst"] if k2[:4] != key[:4]]
                mode = key[3]
                if STORE_CANVAS and 0 < mode < 0x80:
                    # a store into the canvas, write-only: its bytes whole
                    # (the first byte's pixels left of it black, as the
                    # blitter's), the spill byte its carry alone (black
                    # right of it: not read)
                    row0 = key[2]
                    for rr in range(im.rows):
                        r = row0 + rr
                        if not R0 <= r < R1:
                            continue
                        fb, lb = x >> 2, (x + 4 * im.w - 1) >> 2
                        for c in range(fb, lb + 1):
                            if not 0 <= c < 40:
                                continue
                            v = 0
                            for qq in range(4):
                                px = 4 * c + qq - x
                                if 0 <= px < 4 * im.w:
                                    pv = im.px(rr, px, key[1])
                                elif SPILL_BG and FLOOR0 <= r < FLOOR1 and r % 2 == 0:
                                    pv = 2               # (either edge: the floor's stripe)
                                else:
                                    pv = 0
                                v |= pv << (6 - 2 * qq)
                            b["canvas"][(r - R0) * 40 + c] = v
                    continue
                b["inst"].append(key)
            elif k == "F":
                if q[10] != "0":
                    continue
                b = bufs[q[1]]
                kind = q[2]
                c0, c1, bot, top = int(q[3]), int(q[4]), int(q[5]), int(q[6])
                v02, v12 = int(q[8], 16), int(q[9], 16)
                if top >= 0xDD:
                    top = 0
                if c0 >= 40:
                    if c1 >= 41:
                        continue
                    c0 = 0
                c1 = min(c1, 40)
                # into the canvas (rows top to bot - 1: rect v02; pattern
                # v02 on the bottom row, alternating)
                for r in range(max(top, R0), min(bot, R1)):
                    v = v02 if (kind == "rect" or (bot - 1 - r) % 2 == 0) else v12
                    for c in range(c0, c1):
                        b["canvas"][(r - R0) * 40 + c] = v
                # instances whose middle it covers: out
                keep = []
                for key in b["inst"]:
                    src, mir, row, mode, x = key
                    im = imgs[src]
                    mr = (row + row + im.rows) // 2
                    mc = x + 2 * im.w
                    if top <= mr < bot and 4 * c0 <= mc < 4 * c1:
                        continue
                    keep.append(key)
                b["inst"] = keep
        pend = []
        if modes.get(n, (None, None, None))[1] != scene:
            continue
        b = bufs[drawn]
        cv = b["canvas"]
        pic = [[(cv[r * 40 + (c >> 2)] >> (6 - 2 * (c & 3))) & 3 for c in range(160)] for r in range(R1 - R0)]
        for src, mir, row, mode, x in b["inst"]:
            im = imgs[src]
            for rr in range(im.rows):
                r = row + rr
                if not R0 <= r < R1:
                    continue
                for xx in range(4 * im.w):
                    sx = x + xx
                    if not 0 <= sx < 160:
                        continue
                    v = im.px(rr, xx, mir)
                    if mode == 0xFF:
                        if v == 0:
                            pic[r - R0][sx] = 0
                    elif mode == 0:
                        if v:
                            pic[r - R0][sx] = v
                    else:
                        pic[r - R0][sx] = v
        real = bytes.fromhex(p[5] if drawn == "A" else p[7])
        diff = 0
        for r in range(R1 - R0):
            for c in range(160):
                rv = (real[r * 40 + (c >> 2)] >> (6 - 2 * (c & 3))) & 3
                if rv != pic[r][c]:
                    diff += 1
        out.append((n, diff, len(b["inst"])))
        if png and show == n:
            from PIL import Image
            PAL = [(0, 0, 0), (230, 150, 120), (110, 160, 240), (240, 240, 240)]
            im = Image.new("RGB", (160, 2 * (R1 - R0) + 4), (255, 0, 255))
            for r in range(R1 - R0):
                for c in range(160):
                    im.putpixel((c, r), PAL[pic[r][c]])
                    rv = (real[r * 40 + (c >> 2)] >> (6 - 2 * (c & 3))) & 3
                    im.putpixel((c, R1 - R0 + 4 + r), PAL[rv])
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
        hist = Counter(min(r[1] // 100, 10) for r in bad)
        print("   pixels/100:", dict(sorted(hist.items())))
        print("   first:", bad[:12])


if __name__ == "__main__":
    main()
