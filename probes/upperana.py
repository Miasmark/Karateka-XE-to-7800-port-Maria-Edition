"""What the original draws in buffer rows LO-HI (default 45-78), from
probes/xe-bandlog.lua runs: per image (source, size), the draws whose rows
meet the range, by caller, how many distinct columns, how often a picture,
and the fills there.

    python probes/upperana.py [LO HI] work/analysis/bl-s1 [...]
Only what is drawn while the run's own scene (the number ending the
directory's name, bl-s<N>) is loaded counts."""
import collections
import os
import sys

args = sys.argv[1:]
LO, HI = (int(args.pop(0)), int(args.pop(0))) if args and args[0].isdigit() else (45, 78)
for d in args:
    want = int(d.rstrip("/").split("bl-s")[-1]) if "bl-s" in d else None
    pics = set()
    img = collections.defaultdict(lambda: {"n": 0, "cols": set(), "callers": set(), "rows": set(), "pics": set()})
    fills = collections.Counter()
    for line in open(os.path.join(d, "bandlog.log")):
        t = line.split()
        if t[0] == "P":
            pics.add(int(t[2]))
        elif t[0] == "B":
            f, flip, sc, kind, src, bank, rows, width, caller, col, top, shift, mode, buf = t[1:]
            if want is not None and int(sc) != want:
                continue
            r0 = int(top) - 35
            r1 = r0 + int(rows) - 1
            if r1 < LO or r0 > HI:
                continue
            k = (src, int(rows), int(width), kind in ("M", "MR"))
            e = img[k]
            e["n"] += 1; e["cols"].add(int(col)); e["callers"].add(caller); e["rows"].add(r0); e["pics"].add(int(flip))
        elif t[0] == "F":
            f, flip, sc, kind, c0, top, c1, bottom, caller, buf = t[1:11]
            if want is not None and int(sc) != want:
                continue
            r0, r1 = int(top) - 35, int(bottom) - 36
            if r1 < LO or r0 > HI:
                continue
            fills[(kind, caller, int(c0), int(c1), max(r0, LO), min(r1, HI))] += 1
    print("%s: rows %d-%d, %d pictures" % (d, LO, HI, len(pics)))
    print("  images (src rows x width, mirrored): draws, pictures with it, columns, top rows, callers")
    tot = 0
    for k, e in sorted(img.items(), key=lambda kv: -kv[1]["n"]):
        src, rows, width, mir = k
        tot += rows * width
        print("   $%s %3dx%-2d %s  %6d draws %5d pics  cols %-3d tops %s  %s" % (
            src, rows, width, "M" if mir else " ", e["n"], len(e["pics"]), len(e["cols"]),
            ",".join(str(r) for r in sorted(e["rows"])[:6]) + ("..." if len(e["rows"]) > 6 else ""),
            " ".join(sorted(e["callers"]))))
    print("  distinct images: %d, %d bytes" % (len(img), tot))
    print("  fills meeting the rows (kind caller cols rows: count), top 12:")
    for (kind, caller, c0, c1, r0, r1), n in fills.most_common(12):
        print("   %-7s %s cols %2d-%2d rows %3d-%3d: %d" % (kind, caller, c0, c1 - 1, r0, r1, n))
