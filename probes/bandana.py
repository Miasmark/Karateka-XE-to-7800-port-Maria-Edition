"""The fighters as MARIA objects, measured from the original's drawing
(probes/xe-bandlog.lua runs): per picture, the actors drawn (fighters,
the hawk, Mariko: art-bank sources, not the doorways), and what else
writes into the fighter band.

    python probes/bandana.py work/analysis/bl-s1 [...]

Per scene, over the pictures with actors in them (avg / 95% / max):
- parts: the actors' blits (masks AND, sprites OR)
- part bytes: rows x width of every actor blit, masks and sprites, +1
  byte a row for a part not on a byte boundary (what separate objects
  copied to RAM would hold)
- boxes: the actors' parts grouped by overlap, each group's bounding box
  (what one composed buffer a group would hold), in bytes
- band rows: the rows any actor covers
- wipes: fill bytes over the actors' old boxes (the fills overlapping an
  actor's box that picture or the one before in the same buffer)
- other band bytes: blit and fill bytes in the band (buffer rows 79-128)
  from anything else
Geometry: buffer row = $06 - 35; left pixel = 4 x column + shift / 2,
the column being the right byte for the right-aligned kinds (AR, MR).
"""
import collections
import os
import sys

BAND = (79, 128)
DOOR = (0xB800, 0xBA00)          # the doorways' callers (bank 15, from the art bank)
SCENERY = [(0x7110, 0x7140)]     # level 3's door frames scrolling in (scene code, from the art bank)


def parse(d):
    pics = collections.defaultdict(lambda: {"B": [], "F": []})
    scene = {}
    for line in open(os.path.join(d, "bandlog.log")):
        t = line.split()
        if t[0] == "B":
            f, flip, sc, kind, src, bank, rows, width, caller, col, top, shift, mode, buf = t[1:]
            pics[int(flip)]["B"].append(dict(kind=kind, src=int(src, 16), rows=int(rows), width=int(width),
                                             caller=int(caller, 16), col=int(col), top=int(top),
                                             shift=int(shift), mode=int(mode), buf=buf))
            scene[int(flip)] = int(sc)
        elif t[0] == "F":
            f, flip, sc, kind, c0, top, c1, bottom, caller, buf = t[1:11]
            pics[int(flip)]["F"].append(dict(kind=kind, c0=int(c0), top=int(top), c1=int(c1),
                                             bottom=int(bottom), caller=int(caller, 16), buf=buf))
    return pics, scene


def rect(b):
    """a blit's pixels: (x0, x1, row0, row1), inclusive"""
    col = b["col"] - b["width"] + 1 if b["kind"] in ("AR", "MR") else b["col"]
    x0 = 4 * col + b["shift"] // 2
    return x0, x0 + 4 * b["width"] - 1, b["top"] - 35, b["top"] - 35 + b["rows"] - 1


def frect(fl):
    """a fill's pixels (columns c0 to c1 exclusive, lines top to bottom exclusive)"""
    return 4 * fl["c0"], 4 * fl["c1"] - 1, fl["top"] - 35, fl["bottom"] - 36


def overlap(a, b):
    return a[0] <= b[1] and b[0] <= a[1] and a[2] <= b[3] and b[2] <= a[3]


def is_actor(b):
    return (0x8000 <= b["src"] < 0xA000 and not (DOOR[0] <= b["caller"] < DOOR[1])
            and not any(lo <= b["caller"] < hi for lo, hi in SCENERY))


def groups(rects):
    gs = []
    for r in rects:
        hit = [g for g in gs if any(overlap(r, q) for q in g)]
        merged = [r] + [q for g in hit for q in g]
        gs = [g for g in gs if g not in hit] + [merged]
    return gs


def box_bytes(g):
    x0 = min(r[0] for r in g); x1 = max(r[1] for r in g)
    y0 = min(r[2] for r in g); y1 = max(r[3] for r in g)
    return (x1 // 4 - x0 // 4 + 1) * (y1 - y0 + 1), (y0, y1)


def stats(v):
    v = sorted(v)
    if not v:
        return "-"
    return "%d / %d / %d" % (sum(v) / len(v), v[int(len(v) * 0.95)], v[-1])


def main():
    for d in sys.argv[1:]:
        pics, scene = parse(d)
        rows = collections.defaultdict(list)
        last_box = {}
        srcs = {}
        for n in sorted(pics):
            p = pics[n]
            act = [b for b in p["B"] if is_actor(b)]
            if not act:
                continue
            buf = act[0]["buf"]
            rs = [rect(b) for b in act]
            part = sum(b["rows"] * (b["width"] + (1 if b["shift"] // 2 % 4 else 0)) for b in act)
            gs = groups(rs)
            boxes = [box_bytes(g) for g in gs]
            prev = last_box.get(buf, [])
            here = [(min(r[0] for r in g), max(r[1] for r in g), min(r[2] for r in g), max(r[3] for r in g))
                    for g in gs]
            wipe = other = 0
            for fl in p["F"]:
                fr = frect(fl)
                nbytes = (fl["c1"] - fl["c0"]) * max(0, fl["bottom"] - fl["top"])
                if any(overlap(fr, q) for q in here + prev):
                    wipe += nbytes
                elif fr[2] <= BAND[1] and fr[3] >= BAND[0]:
                    other += nbytes
            for b in p["B"]:
                if is_actor(b):
                    continue
                r = rect(b)
                if r[2] <= BAND[1] and r[3] >= BAND[0]:
                    other += b["rows"] * b["width"]
            last_box[buf] = here
            for b in act:
                srcs[(b["src"], b["kind"] in ("M", "MR"))] = b["rows"] * b["width"]
            rows["parts"].append(len(act))
            rows["part bytes"].append(part)
            rows["boxes"].append(sum(x for x, _ in boxes))
            rows["box count"].append(len(boxes))
            rows["band rows"].append(max(y for _, (y0, y) in boxes) - min(y0 for _, (y0, y) in boxes) + 1)
            rows["top row"].append(min(y0 for _, (y0, y) in boxes))
            rows["bottom row"].append(max(y for _, (y0, y) in boxes))
            rows["wipes"].append(wipe)
            rows["other band bytes"].append(other)
        print("%s: %d pictures with actors" % (d, len(rows["parts"])))
        for k in ("parts", "part bytes", "boxes", "box count", "band rows", "wipes", "other band bytes"):
            print("  %-17s %s" % (k, stats(rows[k])))
        if rows["top row"]:
            print("  actors' rows      %d-%d" % (min(rows["top row"]), max(rows["bottom row"])))
        plain = sum(v for (s, m), v in srcs.items() if not m)
        mirr = sum(v for (s, m), v in srcs.items() if m)
        print("  distinct images drawn: %d plain (%d bytes), %d mirrored (%d bytes)" % (
            sum(1 for k in srcs if not k[1]), plain, sum(1 for k in srcs if k[1]), mirr))


if __name__ == "__main__":
    main()
