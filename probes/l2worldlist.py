"""Level 2's worlds' placement list (FINDINGS "Towards no cart RAM"), as
probes/l1worldlist.py makes level 1's: from p7800-l1cap.lua logs and their
state records, which draws sit at one place in a world (world x = screen x +
V, V = 4 x $52 + $50 / 2), to port/l2world.txt.

A buffer's world follows what the game draws into it: the fortress ("2")
from the stakes (every view draws them), the princess's cell ("2c", its x
is screen x: it is drawn at V 1,016, the fortress's end's view too) from its
left wall; a clear unsets it, a copy copies it.

A world's list: its draws in the order of their last occurrence, blits seen
at that place in two pictures or more (the art bank's in twenty, as level
1's), fills painting something other than the rows' base. The rest are
objects (the inventory, port/s2shapes.txt: probes/objinventory.py).

    python probes/l2worldlist.py [--check] LOG:STATE.BIN [...]
--check: each picture's world rendered against the game's buffer, the
objects' pixels left out: the pixels that differ."""
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "port"))
from l1worldlist import state_mode, signed      # noqa: E402

SCENE = 2
STAKES = {0xA4F0, 0xA4D8}       # (the fortress's marker)
CELL = (0x964A, "MR", 60)       # (the cell's: its left wall)
BED = 0xB7C8                    # (the princess's room, "2p": her bed; its wall is the cell's)
ROOM_FLOOR = ("pat", 118, 145, 0xAA, 0x00)   # (a room's floor, its first draw after the clear)
ROOMS = ("2c", "2p")
ART_STILL = 20
V_WRAP = 64
R0, R1 = 65, 146
# the fortress's rows: the palisade's beam (rows 65-66: $AA, the stakes
# over it), black, the floor's stripes ($55 on odd rows: drawn once, the
# same wherever the view is)
BASE = {"2": [(65, 67, 0xAA)] + [(r, r + 1, 0x55 if r % 2 else 0x00) for r in range(118, 146)], "2c": [], "2p": []}
# objects, not tiles: the stakes and spikes (their places follow the view
# but for the game's rounding of its half pixels: 1-3 pixels off at times,
# against their rows above in the top pieces, drawn where the game draws)
OBJECTS = {0xA4F0, 0xA4D8, 0xA5B8}
# the fortress's own images (its world): the gate's pieces and the end walls;
# every other image of the scene page is an object (the portcullis, a line
# at a time; the hawk; the masks), as are the art bank's but in the cell
WORLD_IMAGES = {"2": {0xA103, 0xA12D, 0xA1EC, 0xA000, 0xA274, 0xA602, 0xA546}}
# the rooms' figures, objects too: Akuma's pieces in the cell (his arm's
# poses change), the princess's in her room
FIGURES = {0x974B, 0x984F, 0x9F8C, 0x9EB8, 0x9A62, 0x98D3, 0x9FC4, 0x9FD8, 0x9858, 0x985C,
           0x9908, 0x9956, 0xB300, 0xB33E, 0xB36D}


DIMS = {}                       # (each image's rows and width: the logs')


def base_byte(w, r):
    for a, e, v in BASE[w]:
        if a <= r < e:
            return v
    return 0


def pictures(logs):
    """each picture of SCENE: (n, buffer drawn, V, world, [(buf, draw, world, ref)])"""
    for log, st in logs:
        modes = state_mode(st)
        world = {}
        dims = {}
        pend = []
        bed = set()
        for line in open(log):
            p = line.split()
            if p[0] == "I":
                d = bytes.fromhex(p[3])
                dims.setdefault(int(p[1], 16), (d[0], d[1]))
                DIMS.setdefault(int(p[1], 16), (d[0], d[1]))
                continue
            if p[0] != "P":
                pend.append(p)
                continue
            n, drawn = int(p[1]), p[2]
            z = bytes.fromhex(p[3])
            V = 4 * z[0] + z[1] // 2
            if V < V_WRAP:              # (the level starts at V 0: 1,024, wrapped;
                V += 1024               # then 1,023 down to 112, the gate)
            ours = modes.get(n, (0, 0, 0))[1] == SCENE
            out = []
            for q in pend:
                if q[0] == "C":
                    world[q[1]] = None
                    continue
                if q[0] == "K":
                    world[q[1]] = world.get("B" if q[1] == "A" else "A")
                    continue
                if q[0] == "B":
                    src, bk = int(q[7], 16), int(q[8])
                    if src in STAKES:
                        world[q[1]] = "2"
                    elif (src, q[2], int(q[5])) == CELL and world.get(q[1]) not in ROOMS:
                        world[q[1]] = "room"
                    elif src == BED:
                        bed.add(q[1])
                    rows, w = dims[src]
                    col = signed(int(q[4]))
                    if q[2] in ("AR", "MR"):
                        col -= w - 1
                    d = ("B", src, bk, q[2], int(q[3], 16), int(q[5]), 4 * col + (int(q[6]) >> 1))
                elif q[0] == "F" and q[10] == "0":
                    c0, c1, bot, top = int(q[3]), int(q[4]), int(q[5]), int(q[6])
                    if top >= 0xDD:
                        top = 0
                    if c0 >= 40:
                        if c1 >= 41:
                            continue
                        c0 = 0
                    c1 = min(c1, 40)
                    d = ("F", q[2], top, bot, int(q[8], 16), int(q[9], 16), 4 * c0, 4 * c1)
                    if d[1:6] == ROOM_FLOOR:
                        world[q[1]] = "room"
                else:
                    continue
                out.append([q[1], d, world.get(q[1]), V])
            pend = []
            # (a room drawn in this picture: the princess's if her bed is
            # in it, else the cell; its draws so far its)
            for b in ("A", "B"):
                if world.get(b) == "room":
                    world[b] = "2p" if b in bed else "2c"
                    for o in out:                   # (and since its clear, before
                        if o[0] == b and o[2] in ("room", None):     # its marker)
                            o[2] = world[b]
                            o.append("first")       # (the room's own picture)
            bed = set()
            for o in out:
                if o[2] in ROOMS:
                    o[3] = 0
            out = [tuple(o) for o in out]
            if ours:
                yield n, drawn, V, world.get(drawn), out, (log, p)


def placements(logs):
    last, seen = {}, defaultdict(set)
    based = set()
    seqs = []                           # (each picture's keys in order: who comes first)
    t = 0
    for n, drawn, V, w0, draws, _ in pictures(logs):
        seqs.append([])
        for o in draws:
            buf, d, w, ref = o[:4]
            if w is None:
                continue
            # (a room is drawn whole in one picture after its clear: its
            # world is that picture's draws; the erases after, its figures
            # moving, are not)
            if w in ROOMS and len(o) < 5:
                continue
            t += 1
            if d[0] == "B":
                if d[1] in OBJECTS or d[1] in FIGURES or (w in WORLD_IMAGES and d[1] not in WORLD_IMAGES[w]):
                    continue
                key = (w,) + d[:6] + (d[6] - ref,)
                seen[key].add(n)
            else:
                kind, top, bot, v02, v12 = d[1:6]
                rows = range(max(top, R0), min(bot, R1))
                if not rows:
                    continue
                vals = [(v02 if (kind == "rect" or (bot - 1 - r) % 2 == 0) else v12, r) for r in rows]
                key = (w, "F", kind, top, bot, v02, v12, d[6] - ref, d[7] - ref)
                if all(base_byte(w, r) == v for v, r in vals):
                    based.add(key)          # (the base again: kept only over a draw kept)
                seen[key].add(n)
            last[key] = t
            seqs[-1].append(key)
    out = defaultdict(list)
    for key in order(last, seqs):
        # (the cell is drawn once, then holds: one picture is enough there)
        need = 1 if key[0] in ("2c", "2p") else (2 if key[1] == "F" else (
            ART_STILL if 0x8000 <= key[2] < 0xA000 or key[3] == 6 else 2))
        if len(seen[key]) < need:
            continue
        if key in based and not any(overlap(key[1:], d) for d in out[key[0]]):
            continue
        out[key[0]].append(key[1:])
    return out


def order(last, seqs):
    """the keys in the order of their last occurrence, but each overlapping
    pair as it comes in most pictures with both (the gate's tips after its
    pieces, though the portcullis's drop draws them last elsewhere)"""
    first = sorted(last, key=lambda k: last[k])
    rank = {k: i for i, k in enumerate(first)}
    before = defaultdict(int)
    for s in seqs:
        pos = {}
        for i, k in enumerate(s):
            pos.setdefault(k, i)
        ks = sorted(pos, key=lambda k: pos[k])
        for i, k in enumerate(ks):
            for j in ks[i + 1:]:
                before[(k, j)] += 1
    after = defaultdict(set)            # (k: the keys that must come before it)
    for (k, j), c in before.items():
        if c > before.get((j, k), 0) and k[0] == j[0] and overlap(k[1:], j[1:]) and rank[k] > rank[j]:
            after[j].add(k)
    out, done = [], set()
    while len(out) < len(first):
        k = next((k for k in first if k not in done and not (after[k] - done)), None)
        if k is None:                   # (a cycle: the last occurrence decides)
            k = next(k for k in first if k not in done)
        out.append(k)
        done.add(k)
    return out


def overlap(f, d):
    """fill f (in placements' form) over the rows and columns of a draw d
    before it (a fill's rectangle; a blit's, from its image's size)"""
    if f[0] == "F":
        top, bot, x0, x1 = max(f[2], R0), min(f[3], R1), f[6], f[7]
    else:
        rows, w = DIMS.get(f[1], (0, 0))
        top, bot, x0, x1 = max(f[5], R0), min(f[5] + rows, R1), f[6], f[6] + 4 * w
    if d[0] == "F":
        a, b, y0, y1 = d[2], d[3], d[6], d[7]
    else:
        rows, w = DIMS.get(d[1], (0, 0))
        a, b, y0, y1 = d[5], d[5] + rows, d[6], d[6] + 4 * w
    return a < bot and top < b and y0 < x1 and x0 < y1


SHOW = {int(x) for x in os.environ.get("SHOW", "").split(",") if x}
SHOWDIR = os.environ.get("SHOWDIR", ".")


def check(logs):
    """each picture's world rendered (port/l1world7800.py's renderer) at its
    view against the game's buffer: its pixels that differ"""
    import l1world7800 as LW
    import l1scene7800 as LS
    get = LS.cart_get(os.path.join(HERE, "..", "work", "karateka7800.a78"))
    for w, b in BASE.items():
        LW.BASE[w] = tuple(b)
    draws = LW.load(os.path.join(HERE, "..", "port", "l2world.txt"))
    cvs = {w: LW.render(w, draws[w], get, -1100, 300) for w in draws}
    res = []
    for n, drawn, V, w0, _, (log, p) in pictures(logs):
        if w0 not in cvs:
            res.append((n, None))
            continue
        cv = cvs[w0]
        ref = 0 if w0 in ("2c", "2p") else V
        real = bytes.fromhex(p[5] if drawn == "A" else p[7])
        diff = 0
        for r in range(R0, R1):
            for x in range(160):
                rv = (real[(r - R0) * 40 + (x >> 2)] >> (6 - 2 * (x & 3))) & 3
                if cv.get(r, x - ref) != rv:
                    diff += 1
        res.append((n, diff))
        if SHOW and n in SHOW:
            from PIL import Image
            PAL = [(0, 0, 0), (230, 150, 120), (110, 160, 240), (240, 240, 240)]
            im = Image.new("RGB", (160, 2 * (R1 - R0) + 4), (255, 0, 255))
            for r in range(R0, R1):
                for x in range(160):
                    im.putpixel((x, r - R0), PAL[cv.get(r, x - ref)])
                    im.putpixel((x, R1 - R0 + 4 + r - R0), PAL[(real[(r - R0) * 40 + (x >> 2)] >> (6 - 2 * (x & 3))) & 3])
            im.resize((640, im.height * 4), Image.NEAREST).save(os.path.join(SHOWDIR, "l2w_%d.png" % n))
    bad = [r for r in res if r[1]]
    print("%d pictures, %d with no world, %d differ" % (len(res), sum(1 for r in res if r[1] is None), len(bad)))
    print(Counter(min((r[1] or 0) // 100, 20) for r in res))
    print([r for r in res if r[1]][:30])


def main():
    logs = [tuple(a.rsplit(":", 1)) for a in sys.argv[1:] if ":" in a and not a.startswith("--")]
    if "--check" in sys.argv:
        check(logs)
        return
    lists = placements(logs)
    # each world's range in world x the screen shows (screen x - V)
    ranges = {}
    for n, drawn, V, w0, _, _ in pictures(logs):
        if w0:
            ref = 0 if w0 in ROOMS else V
            a, b = ranges.get(w0, (10 ** 6, -10 ** 6))
            ranges[w0] = (min(a, -ref), max(b, 160 - ref))
    path = os.path.join(HERE, "..", "port", "l2world.txt")
    with open(path, "w", newline="\n") as f:
        f.write("# level 2's worlds (probes/l2worldlist.py): each world's draws in order, at world x\n"
                "# (screen x - V; the rooms', 2c and 2p: screen x)\n"
                "# B world src bank kind mode row x | F world kind top bottom v02 v12 x0 x1 |\n"
                "# R world x0 x1: what the screen shows\n")
        for w in sorted(ranges):
            f.write("R %s %d %d\n" % (w, ranges[w][0], ranges[w][1]))
        for w in sorted(lists):
            for d in lists[w]:
                if d[0] == "B":
                    f.write("B %s %04X %d %s %02X %d %d\n" % (w, d[1], d[2], d[3], d[4], d[5], d[6]))
                else:
                    f.write("F %s %s %d %d %02X %02X %d %d\n" % ((w,) + d[1:]))
    for w in sorted(lists):
        print("%s: %d draws" % (w, len(lists[w])))
    print("to", path)


if __name__ == "__main__":
    main()
