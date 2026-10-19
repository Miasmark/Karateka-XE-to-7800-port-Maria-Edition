"""Level 1's worlds' placement list from capture logs (p7800-l1cap.lua) and
the recording's game state (p7800-staterec.lua's state.bin): which draws sit
at one place in a world (world x = screen x - V, V = 4 x $52 + $50 / 2).

A buffer's world follows what the game draws into it: the cutscene's room
("c", screen-fixed: its x is screen x) from the room's floor (a pattern
fill over rows 118-145, ROOM_FILL), the structure $4C (0, 1) again from the
rails' blit (RAILS_SRC; every view of the level draws them). ($1A0B, the
game's mode, is 2 for the cutscene but a picture late at its start and
still 2 for the level's first pictures after it.)

    python probes/l1worldlist.py LOG STATE.BIN [--stats]

--stats: each world's draws (blits and column stacks by image, kind, mode,
row; fills by kind, rows and values) with their world places' counts.
"""
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
# the posts, the mountain's base: objects; and the mountain's edge over the
# cliff, $AB4A, drawn at the screen's left in every picture (screen-fixed, as
# the base is: the user, "a small portion of the background mountain"),
# with its AND mask $AB94 after it (an object too, so it masks the edge)
OBJECTS = {0xAA23, 0xAA31, 0xA9B8, 0xA9E2, 0xAB4A, 0xAB94}


def signed(c):
    return c - 256 if c >= 128 else c


def state_mode(path):
    """flip -> ($1A0B, $D0, $E9)"""
    addrs = [int(l, 16) for l in open(os.path.join(HERE, "..", "work", "gamestate.txt"))]
    blob = open(path, "rb").read()
    n = len(addrs)
    i, j, k = addrs.index(0x1A0B), addrs.index(0x00D0), addrs.index(0x00E9)
    return {f + 1: (blob[f * n + i], blob[f * n + j], blob[f * n + k]) for f in range(len(blob) // n)}


def level_world(s4c, e9):
    """the structure's world: structure 0 before the cutscene ($E9 0) and
    after it ($E9 1: "0b") differ"""
    return str(s4c) + ("b" if (e9 and s4c == 0) else "")


SCENE = 1                       # (level 1's own pictures: $D0)
ROOM_FILL = ("pat", 118, 145)   # (kind, top, bottom: the cutscene room's floor)
RAILS_SRC = 0xAA11


def pictures(log, modes):
    """each picture: (n, drawn buffer, V, world, [draws]); a draw is
    ("B", src, kind, mode, row, x) / ("L", src, kind, row, lim, x) /
    ("F", kind, top, bot, v02, v12, x0, x1, clipped-left, clipped-right) at
    screen x (pixels); C/K kept for the buffers"""
    dims = {}
    pend = []
    for line in open(log):
        p = line.split()
        t = p[0]
        if t == "I":
            d = bytes.fromhex(p[3])
            dims[int(p[1], 16)] = (d[0], d[1])
            continue
        if t != "P":
            pend.append(p)
            continue
        n, drawn = int(p[1]), p[2]
        z = bytes.fromhex(p[3])
        V, s4c = 4 * z[0] + z[1] // 2, z[2]
        mode, d0, e9 = modes.get(n, (None, None, None))       # (e9: console $00E9, the game's $30)
        lw = level_world(s4c, e9)
        if d0 != SCENE:
            pend = []
            continue
        draws = []
        for q in pend:
            if q[0] == "B":
                src = int(q[7], 16)
                rows, w = dims[src]
                col = signed(int(q[4]))
                if q[2] in ("AR", "MR"):
                    col -= w - 1
                draws.append((q[1], ("B", src, q[2], int(q[3], 16), int(q[5]), 4 * col + (int(q[6]) >> 1))))
            elif q[0] == "L":
                src, col, row, sh, lim = int(q[2], 16), signed(int(q[3])), int(q[4]), int(q[5]), int(q[6])
                entry, z52 = q[8], int(q[9])
                if src < 0xA000 or (entry == "68" and (z52 >= 0x80 or z52 < 0x14)):
                    continue
                draws.append((q[1], ("L", src, "A", row, lim, 4 * col + (sh >> 1))))
            elif q[0] == "F":
                kind = q[2]
                c0, c1, bot, top, v02, v12, nofill = int(q[3]), int(q[4]), int(q[5]), int(q[6]), int(q[8], 16), int(q[9], 16), int(q[10])
                if top >= 0xDD:
                    top = 0
                cl, cr = c0 >= 40 or c0 == 0, c1 >= 40
                if c0 >= 40:
                    c0 = None if c1 >= 41 else 0
                elif c1 >= 41:
                    c1 = 40
                if nofill or c0 is None:
                    continue
                draws.append((q[1], ("F", kind, top, bot, v02, v12, 4 * c0, 4 * c1, cl, cr)))
            elif q[0] in ("C", "K"):
                draws.append((q[1], (q[0],)))
        pend = []
        # each draw's world and reference (V; the room: 0), by its buffer's
        out = []
        for buf, d in draws:
            if d[0] == "F" and d[1:4] == ROOM_FILL:
                WORLD[buf] = "c"
            elif d[0] == "B" and d[1] == RAILS_SRC:
                WORLD[buf] = lw
            elif d[0] == "K":
                WORLD[buf] = WORLD.get("B" if buf == "A" else "A")
            elif d[0] == "C":
                WORLD[buf] = None         # (cleared: nothing shown until a marker)
            elif WORLD.get(buf) not in (None, "c") and WORLD[buf] != lw:
                WORLD[buf] = lw           # (the structure changed under it)
            w = WORLD.get(buf) or lw
            out.append((buf, d, w, 0 if w == "c" else V))
        yield n, drawn, V, WORLD.get(drawn), out


WORLD = {}                      # (each buffer's world, as pictures() goes)


def stats(log, modes):
    places = defaultdict(Counter)
    for n, drawn, V0, w0, draws in pictures(log, modes):
        for buf, d, world, V in draws:
            if d[0] == "B" and d[1] not in OBJECTS:
                places[(world,) + d[:5]][d[5] - V] += 1
            elif d[0] == "L" and d[1] not in OBJECTS:
                places[(world,) + d[:5]][d[5] - V] += 1
            elif d[0] == "F":
                k = (world,) + d[:6]
                places[k][("L%d" % (d[6] - V) if not d[8] else "L-", "R%d" % (d[7] - V) if not d[9] else "R-")] += 1
    for k in sorted(places, key=str):
        c = places[k]
        tot = sum(c.values())
        print("%-46s n %5d places %3d  %s" % (" ".join(str(v) if not isinstance(v, int) or v < 256 else "%04X" % v for v in k),
                                              tot, len(c), " ".join("%s:%d" % (w, m) for w, m in c.most_common(4))))


if __name__ == "__main__":
    log, st = sys.argv[1], sys.argv[2]
    modes = state_mode(st)
    if "--stats" in sys.argv:
        stats(log, modes)


# ---------------------------------------------------------------- the list
BASE = {"0": ((65, 69, 0xAA), (77, 118, 0x00), (118, 146, 0x55)),
        "0b": ((65, 69, 0xAA), (77, 118, 0x00), (118, 146, 0x55)),
        "1": ((65, 69, 0xAA), (77, 118, 0x00), (118, 146, 0x55)),
        "c": ()}                                  # (rows a to e: a byte)
R0, R1 = 65, 146


RAILS = {"0": (0xAA11, 69), "0b": (0xAA11, 69), "1": (0xAA11, 69)}        # (the rails' image and row)
RAILROWS = {}                   # (the rails' rows' bytes: from the log's image)


def base_byte(world, r):
    for a, e, v in BASE[world]:
        if a <= r < e:
            return v
    if world in RAILS and r in RAILROWS:
        return RAILROWS[r]
    return None


def art(src):
    return 0x8000 <= src < 0xA000                 # (the art bank: the figures)


ART_STILL = 20


def views(log, modes):
    """each world's screen range in world x: (least, most + 160)"""
    out = {}
    for n, drawn, V, w0, draws in pictures(log, modes):
        if not w0:
            continue
        ref = 0 if w0 == "c" else V
        a, b = out.get(w0, (10 ** 6, -10 ** 6))
        out[w0] = (min(a, -ref), max(b, 160 - ref))
    return out


def placements(log, modes):
    """each world's draws, in the order of their last occurrence: blits and
    column stacks of the scene page's images (not the objects, not the art
    bank's figures) at world x; fills painting anything but their rows'
    background, at world x"""
    for line in open(log):
        if line.startswith("I AA11 "):
            d = bytes.fromhex(line.split()[3])
            for r in range(d[0]):
                RAILROWS[69 + r] = d[2 + r * d[1]]
            break
    last, seen = {}, defaultdict(set)
    t = 0
    for n, drawn, V0, w0, draws in pictures(log, modes):
        for buf, d, world, V in draws:
            t += 1
            if d[0] in ("B", "L"):
                if d[1] in OBJECTS:
                    continue
                key = (world,) + d[:5] + (d[5] - V,)
                seen[key].add(n)
            elif d[0] == "F":
                kind, top, bot, v02, v12 = d[1:6]
                rows = range(max(top, R0), min(bot, R1))
                if not rows:
                    continue
                # (a row's value: rect v02; pat v02 on the bottom row, alternating)
                vals = [(v02 if (kind == "rect" or (bot - 1 - r) % 2 == 0) else v12, r) for r in rows]
                if all(base_byte(world, r) == v for v, r in vals):
                    continue                      # (its rows' own background: changes nothing)
                key = (world, "F", kind, top, bot, v02, v12, d[6] - V, d[7] - V)
            else:
                continue
            last[key] = t
    out = defaultdict(list)
    for key in sorted(last, key=lambda k: last[k]):
        # (a blit in one picture only, outside the cutscene's room, which is
        # drawn once: animation, the player's climb at the start: an object)
        if key[1] in ("B", "L") and key[0] != "c" and len(seen[key]) == 1:
            continue
        # (the art bank's images, the figures: scenery only where one holds
        # its place for ART_STILL pictures, as the cutscene room's walls do;
        # Akuma's poses come and go)
        if key[1] in ("B", "L") and art(key[2]) and len(seen[key]) < ART_STILL:
            continue
        out[key[0]].append(key[1:])
    return out


def write_list(path, lists, banks, ranges):
    with open(path, "w") as f:
        f.write("# level 1's worlds (probes/l1worldlist.py): each world's draws in order, at world x\n"
                "# (screen x + view, V = 4 x $52 + $50 / 2); its rows' backgrounds first (BASE).\n"
                "# B world src bank kind mode row x | L world src bank kind row lim x |\n"
                "# F world kind top bottom v02 v12 x0 x1 | R world x0 x1: what the screen shows\n")
        for w in sorted(ranges):
            f.write("R %s %d %d\n" % (w, ranges[w][0], ranges[w][1]))
        for w in sorted(lists):
            for d in lists[w]:
                if d[0] in ("B", "L"):
                    f.write("%s %s %04X %d %s %s %d %d\n" % (d[0], w, d[1], banks[d[1]], d[2],
                                                            ("%02X" % d[3]) if d[0] == "B" else str(d[3]), d[4], d[5]))
                else:
                    f.write("F %s %s %d %d %02X %02X %d %d\n" % ((w,) + d[1:]))


if __name__ == "__main__" and "--write" in sys.argv:
    lists = placements(sys.argv[1], state_mode(sys.argv[2]))
    banks = {}
    for l in open(os.path.join(HERE, "..", "port", "l1shapes.txt")):
        p = l.split()
        if p and p[0] in ("B", "L"):
            banks[int(p[1], 16)] = int(p[2])
    for w in lists:
        for d in lists[w]:
            if d[0] in ("B", "L") and d[1] not in banks:
                banks[d[1]] = 1                    # (the scene page)
    out = sys.argv[sys.argv.index("--write") + 1]
    write_list(out, lists, banks, views(sys.argv[1], state_mode(sys.argv[2])))
    print("%s: %s" % (out, ", ".join("world %s %d draws" % (w, len(lists[w])) for w in sorted(lists))))
