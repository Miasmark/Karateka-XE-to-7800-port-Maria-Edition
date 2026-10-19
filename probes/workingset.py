"""The actors as MARIA objects: the RAM a picture needs, from the original's
draw logs (probes/xe-bandlog.lua runs, work/analysis/bl-s*). Each picture's
actor blits in the band (rows 65-145) are grouped by actor (plain blits the
player, mirrored ones the enemy, the hawk's routines its own); a mask goes
with the sprite it overlaps most, and the part is the sprite's coloured
pixels with the mask's cleared ones (the merge: FINDINGS "The fighters'
parts: masks and colours"). Each part is cut at the band's zones and each
slice trimmed to its opaque bytes; a slice needs its width x its zone's
height in RAM (an object reads every line of its zone; RAM has no holey
DMA, so the lines outside the part must hold zeros). Also each actor
composed into one object per zone. Per buffer (a picture), both forms:
bytes, objects in a zone.

    python probes/workingset.py [--zone 16|8] [--layers] work/analysis/bl-s1 [...]
--layers: each part as two objects, its colours (palette 1: all four kept)
and its black pixels (a one-colour layer), instead of grey made white."""
import collections
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import dis as D     # noqa: E402

args = sys.argv[1:]
ZH = 16
LAYERS = "--layers" in args
args = [a for a in args if a != "--layers"]
if args and args[0] == "--zone":
    ZH = int(args[1])
    args = args[2:]
FB_TOP, FB_BAND, LAST = 65, 27, 145
# the band's zones: each buffer column (FB_BAND rows) in zones of at most ZH
ZONES = []
for c0 in range(FB_TOP, LAST + 1, FB_BAND):
    r = c0
    while r < min(c0 + FB_BAND, LAST + 1):
        ZONES.append((r, min(r + ZH, c0 + FB_BAND, LAST + 1) - 1))
        r += ZH
ACTOR_CALLERS = {   # scene: the routines drawing the actors' parts (probes/actorparts.py)
    1: {"7A53", "7A76", "A857", "A887", "A8DF", "A910", "7A98", "7AC7", "A863", "A891", "A8EB", "A91D",
        "7ACF", "7ADA", "B533", "B580"},
    2: {"7B5C", "7B69", "7B78", "7BA0", "7BA8", "7BB3", "A857", "A887", "A8DF", "A910", "A863", "A891",
        "A8EB", "A91D", "B533", "B580"},
    3: {"7AEB", "7B03", "7B18", "7B39", "7B41", "7B4C", "A857", "A887", "A8DF", "A910", "A863", "A891",
        "A8EB", "A91D", "B533", "B580"},
    6: {"7A53", "7A76", "A857", "A887", "A8DF", "A910", "7A98", "7AC7", "A863", "A891", "A8EB", "A91D",
        "7ACF", "7ADA", "B533", "B580"},
}
HAWK = {"7ACF", "7ADA", "B533", "B580", "7BA8", "7BB3", "7B41", "7B4C"}
mem = {}


def pixels(sc, kind, src, col, top, shift, mode):
    """the blit's pixels: (x, y) -> colour for a sprite (non-zero), or the
    cleared ones (0) for a mask"""
    m = mem.setdefault(sc, D.memory(sc))
    rows, w = m.get(src, 0), m.get(src + 1, 0)
    mir = kind in ("M", "MR")
    c = col - w + 1 if kind in ("AR", "MR") else col
    x0 = c * 4 + shift // 2
    out = {}
    for y in range(rows):
        for b in range(w):
            byte = m.get(src + 2 + y * w + b, 0)
            for k in range(4):
                v = (byte >> (6 - 2 * k)) & 3
                px = (w - 1 - b) * 4 + (3 - k) if mir else b * 4 + k
                if mode < 0:
                    if v == 0:
                        out[(x0 + px, top - 35 + y)] = 0
                elif v:
                    out[(x0 + px, top - 35 + y)] = v
    return out


def slices(px):
    """per zone: (zone, first byte, last byte) of a part's opaque pixels"""
    out = []
    for z0, z1 in ZONES:
        xs = [x for (x, y) in px if z0 <= y <= z1]
        if xs:
            out.append(((z0, z1), min(xs) // 4, max(xs) // 4))
    return out


def picture(sc, blits):
    """bytes and the most objects in one zone, for parts and for composed actors"""
    actors = collections.defaultdict(lambda: {"masks": [], "sprites": []})
    for kind, src, col, top, shift, mode, caller in blits:
        who = "hawk" if caller in HAWK else ("enemy" if kind in ("M", "MR") else "player")
        px = pixels(sc, kind, src, col, top, shift, mode)
        if px:
            actors[who]["masks" if mode < 0 else "sprites"].append(px)
    part_bytes, comp_bytes = 0, 0
    zone_objs_p, zone_objs_c = collections.Counter(), collections.Counter()
    for who, a in actors.items():
        parts = [dict(s) for s in a["sprites"]]
        for mk in a["masks"]:                       # the mask joins the sprite it overlaps most
            best = max(range(len(parts)), key=lambda i: len(set(parts[i]) & set(mk)), default=None)
            if best is None:
                parts.append(dict(mk))
            else:
                for xy in mk:
                    parts[best].setdefault(xy, 0)
        for p in parts:
            layers = [{xy: v for xy, v in p.items() if v}, {xy: v for xy, v in p.items() if not v}] if LAYERS else [p]
            for lay in layers:
                for (z0, z1), b0, b1 in slices(lay):
                    part_bytes += (b1 - b0 + 1) * (z1 - z0 + 1)
                    zone_objs_p[(z0, z1)] += 1
        whole = {}
        for p in parts:
            whole.update(p)
        for (z0, z1), b0, b1 in slices(whole):
            comp_bytes += (b1 - b0 + 1) * (z1 - z0 + 1)
            zone_objs_c[(z0, z1)] += 1
    return part_bytes, comp_bytes, max(zone_objs_p.values(), default=0), max(zone_objs_c.values(), default=0)


def main():
    print("zones of at most %d rows: %s" % (ZH, " ".join("%d-%d" % z for z in ZONES)))
    for d in args:
        want = int(d.rstrip("/").split("bl-s")[-1])
        pics = collections.defaultdict(list)
        for line in open(os.path.join(d, "bandlog.log")):
            t = line.split()
            if t[0] != "B" or int(t[3]) != want:
                continue
            f, flip, sc, kind, src, bank, rows, width, caller, col, top, shift, mode, buf = t[1:]
            if caller not in ACTOR_CALLERS.get(want, ()):
                continue
            pics[(int(flip), buf)].append((kind, int(src, 16), int(col), int(top), int(shift), int(mode), caller))
        res = [picture(want, b) for b in pics.values()]
        if not res:
            continue
        for i, name in ((0, "parts"), (1, "composed")):
            v = sorted(r[i] for r in res)
            o = sorted(r[i + 2] for r in res)
            print("scene %d, %d pictures, %-8s bytes a picture: avg %d, 95%% %d, max %d; objects in a zone: max %d"
                  % (want, len(res), name, sum(v) // len(v), v[len(v) * 95 // 100], v[-1], o[-1]))


if __name__ == "__main__":
    main()
