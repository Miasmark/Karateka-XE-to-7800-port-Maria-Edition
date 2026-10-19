"""A tiles scene's worlds' placement list (FINDINGS "Level 2 as tiles",
"Levels 3 and 4 as tiles"; level 2's first as probes/l2worldlist.py): from
p7800-l1cap.lua logs and their state records, which draws sit at one place
in a world, to port/<the scene's world list>. The scene's settings:
port/worldcfg.py.

A scrolled world's x is screen x - V (V = 4 x $52 + $50 / 2; under V_WRAP:
+ 1,024), a room's the screen's. A buffer's world follows the markers in
order (as the runtime's: L1MK_*), a clear unsets it, a copy copies it. A
room is drawn whole in the picture its marker comes in: its draws there
since the clear are its world's (its floor comes before its marker), the
erases after (its figures moving) aren't.

A world's list: its draws, overlapping ones in the order most pictures draw
them (else by their last occurrence); blits seen at that place in two
pictures or more (the art bank's in twenty, as level 1's; a room's in one),
not the objects' images; fills, but one painting the base only over a draw
kept before it. The rest are objects (the inventory: probes/objinventory.py).

    python probes/worldlist.py SCENE [--check] LOG:STATE.BIN [...]
--check: each picture's world rendered against the game's buffer (the
objects' pixels included: they differ)."""
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "port"))
from l1worldlist import state_mode, signed      # noqa: E402
from worldcfg import CFG                        # noqa: E402
import worldcfg as WC                           # noqa: E402

ART_STILL = 20
R0, R1 = 65, 146
C = None                        # (the scene's settings: use())
DIMS = {}                       # (each image's rows and width: the logs')


def use(scene):
    global C
    C = CFG[scene]


def base_byte(w, r):
    for a, e, v in C["base"].get(w, ()):
        if a <= r < e:
            return v
    return 0


def mark(q, world):
    """the world a blit's marker sets for its buffer (q a B line), or None"""
    src, kind, row = int(q[7], 16), q[2], int(q[5])
    for m_src, m_kind, m_row, w, out_only in C["markers"]:
        if src == m_src and m_kind in (None, kind) and m_row in (None, row):
            if out_only and world.get(q[1]) in C["rooms"]:
                return None
            return w
    return None


def pictures(logs):
    """each picture of the scene: (n, buffer drawn, V, world, [(buf, draw, world, ref[, "first"])])"""
    for log, st in logs:
        modes = state_mode(st)
        world = {}
        pend = []
        for line in open(log):
            p = line.split()
            if p[0] == "I":
                d = bytes.fromhex(p[3])
                DIMS.setdefault(int(p[1], 16), (d[0], d[1]))
                continue
            if p[0] != "P":
                pend.append(p)
                continue
            n, drawn = int(p[1]), p[2]
            z = bytes.fromhex(p[3])
            V = 4 * z[0] + z[1] // 2
            if V < C["v_wrap"]:
                V += 1024
            ours = modes.get(n, (0, 0, 0))[1] == C["scene"]
            out = []
            roomed = set()              # (the buffers a room marker came in, this picture)
            for q in pend:
                if q[0] == "C":
                    world[q[1]] = None
                    continue
                if q[0] == "K":
                    world[q[1]] = world.get("B" if q[1] == "A" else "A")
                    continue
                if q[0] == "B":
                    src, bk = int(q[7], 16), int(q[8])
                    w = mark(q, world)
                    if w is not None:
                        world[q[1]] = w
                        if w in C["rooms"]:
                            roomed.add(q[1])
                    rows, iw = DIMS[src]
                    col = signed(int(q[4]))
                    if q[2] in ("AR", "MR"):
                        col -= iw - 1
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
                    rf = C.get("room_floor")
                    if rf and d[1:6] == rf[0]:
                        world[q[1]] = rf[1]
                        roomed.add(q[1])
                else:
                    continue
                out.append([q[1], d, world.get(q[1]), V])
            pend = []
            # (a room marked in this picture: its draws since the clear, and
            # under another room's marker before its own, its own)
            for b in roomed:
                if world.get(b) in C["rooms"]:
                    for o in out:
                        if o[0] == b and o[2] in [None] + C["rooms"]:
                            o[2] = world[b]
                            o.append("first")
            for o in out:
                if o[2] in C["rooms"]:
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
            if w in C["rooms"] and len(o) < 5:
                continue
            t += 1
            if d[0] == "B":
                wi = C["world_images"]
                if (d[1] in C["objects"] or d[1] in C["figures"]
                        or (d[1] in C.get("front", ()) and d[1] not in WC.FRONT_OR)
                        or (w in wi and d[1] not in wi[w])):
                    continue
                key = (w,) + d[:6] + (d[6] - ref,)
                seen[key].add(n)
            else:
                kind, top, bot, v02, v12 = d[1:6]
                rows = range(max(top, R0), min(bot, R1))
                if not rows or (kind, top, bot, v02, v12) in C.get("drop_fills", ()):
                    continue            # (drop_fills: a scene's clears, the base only, before its draws)
                vals = [(v02 if (kind == "rect" or (bot - 1 - r) % 2 == 0) else v12, r) for r in rows]
                key = (w, "F", kind, top, bot, v02, v12, d[6] - ref, d[7] - ref)
                if all(base_byte(w, r) == v for v, r in vals):
                    based.add(key)          # (the base again: kept only over a draw kept)
                seen[key].add(n)
            last[key] = t
            seqs[-1].append(key)
    out = defaultdict(list)
    for key in order(last, seqs):
        need = 1 if key[0] in C["rooms"] else (2 if key[1] == "F" else (
            ART_STILL if 0x8000 <= key[2] < 0xA000 or key[3] == 6 else 2))
        if len(seen[key]) < need:
            continue
        if key in based and not any(overlap(key[1:], d) for d in out[key[0]]):
            continue
        out[key[0]].append(key[1:])
    return out


def order(last, seqs):
    """the keys in the order of their last occurrence, but each overlapping
    pair as it comes in most pictures with both (level 2's gate's tips after
    its pieces, though the portcullis's drop draws them last elsewhere)"""
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
    """draw f (in placements' form) over the rows and columns of a draw d (a
    fill's rectangle; a blit's, from its image's size)"""
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


def main():
    use(int(sys.argv[1]))
    logs = [tuple(a.rsplit(":", 1)) for a in sys.argv[2:] if ":" in a and not a.startswith("--")]
    lists = placements(logs)
    # each world's range in world x the screen shows
    ranges = {}
    for n, drawn, V, w0, _, _ in pictures(logs):
        if w0:
            ref = 0 if w0 in C["rooms"] else V
            a, b = ranges.get(w0, (10 ** 6, -10 ** 6))
            ranges[w0] = (min(a, -ref), max(b, 160 - ref))
    path = os.path.join(HERE, "..", "port", C["out"])
    with open(path, "w", newline="\n") as f:
        f.write("# scene %d's worlds (probes/worldlist.py): each world's draws in order, at world x\n"
                "# (screen x - V; the rooms', %s: screen x)\n"
                "# B world src bank kind mode row x | F world kind top bottom v02 v12 x0 x1 |\n"
                "# R world x0 x1: what the screen shows\n" % (C["scene"], " and ".join(C["rooms"])))
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
