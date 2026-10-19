"""dloverlap2.py DLDUMP2_LOG...: tmp-dldump2.lua's zone lists: every pair of
direct 160A objects in one zone whose columns overlap (x is in pixels, a
160A byte 4 of them), by palettes and by how much they overlap: what a 160B
merge could take (FINDINGS "160A pairs that could be 160B"). A pair inside
one palette group (palettes 0-3 or 4-7) could be one 160B object; across
the groups it couldn't as they are"""
import re
import sys
from collections import Counter

OBJ = re.compile(r"\((\w{4}) pw(\w\w) x(\d+)\)|\[(\w{4}) m(\w\w) pw(\w\w) x(\d+)\]")
by_pal, frac, total, zones = Counter(), Counter(), 0, 0
heights = Counter()
for path in sys.argv[1:]:
    for line in open(path):
        m = re.match(r"\s*z(\d+) line\s+(\d+) h\s*(\d+) f(\w\w) DL \$(\w+):(.*)", line)
        if not m:
            continue
        h, rest = int(m.group(3)), m.group(6)
        wm, objs = 0, []
        for o in OBJ.finditer(rest):
            if o.group(1):
                pw, x, mode = int(o.group(2), 16), int(o.group(3)), None
            else:
                mode, pw, x = int(o.group(5), 16), int(o.group(6), 16), int(o.group(7))
                wm = mode >> 7
            if wm or (mode is not None and mode & 0x40):
                continue
            w = ((-pw) & 0x1F or 32) * 4
            objs.append((x, x + w, pw >> 5))
        zones += 1
        for i in range(len(objs)):
            for j in range(i + 1, len(objs)):
                a, b = objs[i], objs[j]
                ov = min(a[1], b[1]) - max(a[0], b[0])
                if ov > 0 and a[2] != b[2]:
                    total += 1
                    same = (a[2] >> 2) == (b[2] >> 2)
                    by_pal[(min(a[2], b[2]), max(a[2], b[2]), "one group" if same else "two groups")] += 1
                    f = ov / max(a[1] - a[0], b[1] - b[0])
                    frac["exact" if f == 1 else ("over half" if f > 0.5 else "half or less")] += 1
                    heights[h] += 1
print("zones:", zones, " overlapping pairs, different palettes:", total)
for k, n in by_pal.most_common():
    print("   palettes %d+%d (%s): %d" % (k[0], k[1], k[2], n))
print("how much they overlap:", dict(frac))
print("zone heights:", dict(heights))
