"""Level 2 without the blitter, the runtime's model (FINDINGS "Level 2 as
tiles"): each buffer's world as the runtime marks it, its tiles
(port/l2world.txt rendered) under its object instances (level 1's rules),
against the game's own buffers in p7800-l1cap.lua logs.

The world: a clear unsets it, a copy copies it; the stakes mark the
fortress ("2"); the rooms' floor fill, or the cell's wall in a buffer not
in a room, the cell ("2c"); the bed the princess's room ("2p"). The
fortress's tiles at the view (screen x = world x + V), the rooms' fixed.

The instances: a blit of a shape in the set (port/s2shapes.txt less the
worlds' images: OBJ) adds one, or moves it to the end if the same image,
kind, mode, row and place is there; when the picture's view V changed,
those not drawn in it are out; a fill (not a fighter-box erase) takes out
each one whose middle it covers. A store opaque over its rectangle, an OR's
non-zero pixels, an AND mask's pixels by the rule (AMASK: black where
mask & AMASK is 0, else clear).

    python probes/l2tilemodel.py LOG:STATE.BIN [--show N,N --png DIR]
        [--amask N] [--roomobj SRC,SRC]"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "port"))
from l1worldlist import state_mode, signed      # noqa: E402
import l2worldlist as W                           # noqa: E402

R0, R1 = 65, 146
AMASK = int(sys.argv[sys.argv.index("--amask") + 1], 0) if "--amask" in sys.argv else 3
DROP = "--drop" in sys.argv          # (the portcullis's drop as one closed shape at its first line)
ROOMOBJ = {int(x, 16) for x in sys.argv[sys.argv.index("--roomobj") + 1].split(",")} \
    if "--roomobj" in sys.argv else set()


class Img(object):
    def __init__(self, hexs):
        d = bytes.fromhex(hexs)
        self.rows, self.w, self.d = d[0], d[1], d[2:]

    def px(self, r, x, mir):
        if mir:
            x = 4 * self.w - 1 - x
        b = self.d[r * self.w + (x >> 2)]
        return (b >> (6 - 2 * (x & 3))) & 3


def objects():
    """the set's shapes: (src, mirrored, row, mode class) not the worlds'"""
    world_imgs = set(W.WORLD_IMAGES["2"])
    room = set()
    for ln in open(os.path.join(HERE, "..", "port", "l2world.txt")):
        p = ln.split()
        if p and p[0] == "B" and p[1] in W.ROOMS:
            room.add(int(p[2], 16))
    out = set()
    for ln in open(os.path.join(HERE, "..", "port", "s2shapes.txt")):
        p = ln.split()
        if not p or p[0] != "B":
            continue
        src = int(p[1], 16)
        if src in world_imgs or (src in room and src not in ROOMOBJ and src not in W.FIGURES):
            continue
        out.add((src, p[3] == "1", int(p[4])))
    return out


def worlds():
    import l1world7800 as LW
    import l1scene7800 as LS
    get = LS.cart_get(os.path.join(HERE, "..", "work", "karateka7800.a78"))
    for w, b in W.BASE.items():
        LW.BASE[w] = tuple(b)
    draws = LW.load(os.path.join(HERE, "..", "port", "l2world.txt"))
    return {w: LW.render(w, draws[w], get, -1100, 300) for w in draws}


def run(log, st, cvs, objs, show, pngdir):
    modes = state_mode(st)
    imgs = {}
    bufs = {"A": [], "B": []}
    world = {"A": None, "B": None}
    drawn = {"A": set(), "B": set()}
    view = {"A": None, "B": None}
    pend, out = [], []

    def img(src, bk):
        return imgs.get((src, bk)) or next(v for kk, v in imgs.items() if kk[0] == src)

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
        if V < W.V_WRAP:
            V += 1024
        for q in pend:
            k = q[0]
            if k == "C":
                bufs[q[1]] = []
                world[q[1]] = None
            elif k == "K":
                o = "B" if q[1] == "A" else "A"
                bufs[q[1]] = list(bufs[o])
                world[q[1]] = world[o]
                view[q[1]] = view[o]            # (L1Copy: its view and marks too)
                drawn[q[1]] = set(drawn[o])
            elif k == "B":
                src, bk = int(q[7], 16), int(q[8])
                b = q[1]
                if src in W.STAKES:
                    world[b] = "2"
                elif (src, q[2], int(q[5])) == W.CELL and world[b] not in W.ROOMS:
                    world[b] = "2c"
                elif src == W.BED:
                    world[b] = "2p"
                mir = q[2] in ("M", "MR")
                if DROP and src == 0xA0FC and int(q[5]) == 81:
                    src = 0x10FC                # (the closed portcullis: A0FC's line over rows 81-124)
                    if (src, bk) not in imgs:
                        line = img(0xA0FC, bk)
                        imgs[(src, bk)] = Img("%02X%02X" % (44, line.w) + line.d.hex() * 44)
                    objs.add((src, mir, 81))
                if (src, mir, int(q[5])) not in objs:
                    continue
                im = img(src, bk)
                col = signed(int(q[4]))
                if q[2] in ("AR", "MR"):
                    col -= im.w - 1
                x = 4 * col + (int(q[6]) >> 1)
                key = (src, bk, mir, int(q[5]), int(q[3], 16), x)
                if key in bufs[b]:
                    bufs[b].remove(key)
                bufs[b].append(key)
                drawn[b].add(key)
            elif k == "F" and q[10] == "0":
                c0, c1, bot, top = int(q[3]), int(q[4]), int(q[5]), int(q[6])
                if top >= 0xDD:
                    top = 0
                if c0 >= 40:
                    if c1 >= 41:
                        continue
                    c0 = 0
                c1 = min(c1, 40)
                if (q[2], top, bot, int(q[8], 16), int(q[9], 16)) == W.ROOM_FLOOR:
                    world[q[1]] = "2c"
                keep = []
                for key in bufs[q[1]]:
                    im = img(key[0], key[1])
                    mr, mc = key[3] + im.rows // 2, key[5] + 2 * im.w
                    if top <= mr < bot and 4 * c0 <= mc < 4 * c1:
                        continue
                    keep.append(key)
                bufs[q[1]] = keep
        pend = []
        if view[dr] is not None and view[dr] != V:
            bufs[dr] = [k for k in bufs[dr] if k in drawn[dr]]
        view[dr] = V
        drawn[dr] = set()
        if modes.get(n, (0, 0, 0))[1] != W.SCENE:
            continue
        w = world[dr]
        ref = 0 if w in W.ROOMS else V
        if w in cvs:
            cv = cvs[w]
            pic = [[cv.get(r, x - ref) for x in range(160)] for r in range(R0, R1)]
        else:
            pic = [[0] * 160 for r in range(R0, R1)]
        for src, bk, mir, row, mode, x in bufs[dr]:
            im = img(src, bk)
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
                        if not v & AMASK:
                            pic[r - R0][sx] = 0
                    elif mode == 0:
                        if v:
                            pic[r - R0][sx] = v
                    else:
                        pic[r - R0][sx] = v
        real = bytes.fromhex(p[5] if dr == "A" else p[7])
        diff = 0
        for r in range(R1 - R0):
            for c in range(160):
                if (real[r * 40 + (c >> 2)] >> (6 - 2 * (c & 3))) & 3 != pic[r][c]:
                    diff += 1
        out.append((n, diff, w, len(bufs[dr])))
        if pngdir and n in show:
            from PIL import Image
            PAL = [(0, 0, 0), (230, 150, 120), (110, 160, 240), (240, 240, 240)]
            im = Image.new("RGB", (160, 2 * (R1 - R0) + 4), (255, 0, 255))
            for r in range(R1 - R0):
                for c in range(160):
                    im.putpixel((c, r), PAL[pic[r][c]])
                    im.putpixel((c, R1 - R0 + 4 + r), PAL[(real[r * 40 + (c >> 2)] >> (6 - 2 * (c & 3))) & 3])
            im.resize((640, im.height * 4), Image.NEAREST).save(os.path.join(pngdir, "l2t_%d.png" % n))
    return out


def main():
    show = {int(x) for x in sys.argv[sys.argv.index("--show") + 1].split(",")} if "--show" in sys.argv else set()
    pngdir = sys.argv[sys.argv.index("--png") + 1] if "--png" in sys.argv else None
    cvs, objs = worlds(), objects()
    print("%d object shapes" % len(objs))
    for arg in sys.argv[1:]:
        if ":" not in arg or arg.startswith("--") or arg == pngdir:
            continue
        log, st = arg.rsplit(":", 1)
        res = run(log, st, cvs, objs, show, pngdir)
        bad = [r for r in res if r[1]]
        print("%s: %d pictures, %d differ; most instances %d" % (log, len(res), len(bad), max(r[3] for r in res)))
        for w in sorted({r[2] for r in res}, key=str):
            rw = [r for r in res if r[2] == w]
            print("   world %s: %d pictures, %d differ, pixels/100 %s" % (
                w, len(rw), sum(1 for r in rw if r[1]),
                dict(sorted(Counter(min(r[1] // 100, 10) for r in rw if r[1]).items()))))
        print("   worst:", sorted(bad, key=lambda r: -r[1])[:12])


if __name__ == "__main__":
    main()
