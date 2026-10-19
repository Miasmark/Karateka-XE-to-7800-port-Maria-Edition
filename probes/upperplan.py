"""Rows LO-HI (default 45-78) as MARIA objects, costed from the original's
drawing (probes/xe-bandlog.lua runs; FINDINGS "Rows 45-78 as objects: the
costed plan"). Each buffer's pieces there are kept by the top rows' capture
rules (FINDINGS "The top rows as objects"): a blit meeting the rows adds a
piece, and the pieces it spans across their width lose those rows; pieces a fill
it spans across their width lose those rows, and go when none are left (it is
the row's background where it spans the screen's width); a
clear empties the buffer; the buffer copy copies the list. At each flip the
buffer just drawn is measured:
- objects on a line, and MARIA's time there: about 2.25 cycles an object
  and 0.75 a byte (a line has 113.5; FINDINGS "The health arrows and
  MARIA's time");
- list bytes a buffer (4 an object in each TOP_ZONE-row zone, 2 to end each);
- the data the pieces need: their rows within LO-HI, once per image (and
  once per image and top row, as the top rows store them);
- each row's background: the colours of full-width fills there.
Also what doesn't fit the rules: pieces covered in part (a fill or blit
over some of them), and blits that combine (AND/OR) in the rows.

    python probes/upperplan.py [LO HI] work/analysis/bl-s1 [...]
Only what is drawn while the run's own scene (bl-s<N>) is loaded counts."""
import collections
import os
import sys

ZONE = 15


def rect_b(col, kind, width, shift, top, rows):
    c = col - width + 1 if kind in ("AR", "MR") else col
    x0 = 4 * c + shift // 2
    return x0, x0 + 4 * width - 1, top - 35, top - 35 + rows - 1


def cover(lst, r):
    """the pieces left when rectangle r is drawn over them (both clipped to the
    screen, as the top rows' code does; a piece wholly off it goes): a piece loses the
    rows r spans across its whole width, and goes when none are left; (the
    pieces, how many r meets without spanning their width)"""
    keep, part = [], 0
    r = (max(r[0], 0), min(r[1], 159), r[2], r[3])
    for p in lst:
        pr = (max(p["r"][0], 0), min(p["r"][1], 159), p["r"][2], p["r"][3])   # (on screen only,
        if pr[0] > pr[1]:                                                       # as TopVis)
            continue
        if not (r[0] <= pr[1] and pr[0] <= r[1] and r[2] <= pr[3] and pr[2] <= r[3]):
            keep.append(p)
            continue
        if r[0] <= pr[0] and pr[1] <= r[1]:
            p["rows"] -= set(range(r[2], r[3] + 1))
            if p["rows"]:
                keep.append(p)
        else:
            part += 1
            keep.append(p)
    return keep, part


def stats(v):
    v = sorted(v)
    if not v:
        return "-"
    return "%.0f / %.0f / %.0f" % (sum(v) / len(v), v[int(len(v) * 0.95)], v[-1])


def main():
    args = sys.argv[1:]
    LO, HI = (int(args.pop(0)), int(args.pop(0))) if args and args[0].isdigit() else (45, 78)
    for d in args:
        want = int(d.rstrip("/").split("bl-s")[-1])
        bufs = {"40": [], "20": []}
        bg = {"40": {}, "20": {}}
        last_buf = "20"
        m = collections.defaultdict(list)
        images, image_tops = {}, {}
        partial = combine = 0
        bgseen = collections.defaultdict(collections.Counter)
        changes, prev = 0, None
        zmax = {}
        for line in open(os.path.join(d, "bandlog.log")):
            t = line.split()
            if t[0] == "B":
                f, flip, sc, kind, src, bank, rows, width, caller, col, top, shift, mode, buf = t[1:15]
                if int(sc) != want:
                    continue
                r = rect_b(int(col), kind, int(width), int(shift), int(top), int(rows))
                if r[3] < LO or r[2] > HI:
                    continue
                if int(mode) != 1:
                    combine += 1
                keep, n = cover(bufs.setdefault(buf, []), r)
                partial += n
                key = (src, kind in ("M", "MR"))
                keep.append({"r": r, "key": key, "w": int(width), "top": r[2],
                             "rows": set(range(max(r[2], LO), min(r[3], HI) + 1))})
                bufs[buf] = keep
                last_buf = buf
                rr = range(max(r[2], LO), min(r[3], HI) + 1)
                images[key] = len(rr) * int(width)
                image_tops[(key, r[2])] = len(rr) * int(width)
            elif t[0] == "F":
                f, flip, sc, kind, c0, top, c1, bottom, caller, buf = t[1:11]
                colour = int(t[11], 16) & 3 if len(t) > 11 else -1
                if int(sc) != want:
                    continue
                r = (4 * int(c0), 4 * int(c1) - 1, int(top) - 35, int(bottom) - 36)
                if r[3] < LO or r[2] > HI:
                    continue
                keep, n = cover(bufs.setdefault(buf, []), r)
                partial += n
                bufs[buf] = keep
                if int(c0) == 0 and int(c1) >= 40:
                    for row in range(max(r[2], LO), min(r[3], HI) + 1):
                        bg.setdefault(buf, {})[row] = "%s%d" % ("p" if kind == "pattern" else "", colour)
                last_buf = buf
            elif t[0] == "C":
                if int(t[3]) != want:
                    continue
                bufs[t[4]] = []
                bg[t[4]] = {}
            elif t[0] == "K":
                if int(t[3]) != want:
                    continue
                other = "20" if t[4] == "40" else "40"
                bufs[t[4]] = [dict(p, rows=set(p["rows"])) for p in bufs.get(other, [])]
                bg[t[4]] = dict(bg.get(other, {}))
            elif t[0] == "P":
                if int(t[3]) != want:
                    continue
                lst = bufs.get(last_buf, [])
                if not lst:
                    continue
                state = tuple(sorted((p["key"], p["r"], tuple(sorted(p["rows"]))) for p in lst))
                if os.environ.get("DUMPAT") and int(t[2]) == int(os.environ["DUMPAT"]):
                    for p in lst:      # DUMPAT=flip: that picture's pieces
                        print("    %s%s x%d-%d rows %d-%d left %s" % (p["key"][0], " M" if p["key"][1] else "",
                              p["r"][0], p["r"][1], p["r"][2], p["r"][3], sorted(p["rows"])[:3] + ["..."]))
                if state != prev:
                    changes += 1
                prev = state
                worst_obj = worst_t = 0
                for row in range(LO, HI + 1):
                    on = [p for p in lst if row in p["rows"]]
                    tm = sum(2.25 + 0.75 * p["w"] for p in on)
                    worst_obj = max(worst_obj, len(on))
                    worst_t = max(worst_t, tm)
                zones = collections.Counter()
                for p in lst:
                    for z in {row // ZONE for row in p["rows"]}:
                        zones[z] += 1
                m["objects"].append(len(lst))
                m["objects on a line"].append(worst_obj)
                m["MARIA cycles, worst line"].append(worst_t)
                m["list bytes"].append(sum(4 * n + 2 for n in zones.values()))
                for z, n in zones.items():
                    zmax[z] = max(zmax.get(z, 0), n)
                for row in range(LO, HI + 1):
                    bgseen[row][bg.get(last_buf, {}).get(row, "-")] += 1
        print("%s: rows %d-%d" % (d, LO, HI))
        for k in ("objects", "objects on a line", "MARIA cycles, worst line", "list bytes"):
            print("  %-26s %s" % (k, stats(m[k])))
        print("  pictures measured %d, pieces changed in %d" % (len(m["objects"]), changes))
        print("  most objects in a zone (rows): " + " ".join("%d-%d: %d" % (z * ZONE, z * ZONE + ZONE - 1, n)
                                                         for z, n in sorted(zmax.items())))
        print("  data: %d images, %d bytes (by image and top row: %d, %d bytes)" % (
            len(images), sum(images.values()), len(image_tops), sum(image_tops.values())))
        print("  covered in part (a fill or blit over some of a piece): %d; combining blits (AND/OR): %d"
              % (partial, combine))
        rows = []
        for row in range(LO, HI + 1):
            c = bgseen[row]
            rows.append("%d:%s" % (row, "/".join("%s" % k for k, n in c.most_common(2))))
        print("  backgrounds (full-width fills, most seen): " + " ".join(rows))


if __name__ == "__main__":
    main()
