"""dloverlap.py DLDUMP2_LOG...: in tmp-dldump2.lua's zone lists, the 160A
objects that sit exactly on one another (one zone, the same x and width,
direct, not indirect): candidates for one 160B object (FINDINGS "160A pairs
that could be 160B"). The write mode a 5-byte header sets (its mode byte's
bit 7) carries on to the 4-byte headers after it in the list. Counts pairs
by palettes, by flip and zone height, and the cycles a merge would save
(a 4-byte header's DMA: 8 cycles; MARIA's data fetch is the same bytes
either way: 160B holds 2 pixels a byte, two 160A objects 4 each)"""
import re
import sys
from collections import Counter, defaultdict

OBJ = re.compile(r"\((\w{4}) pw(\w\w) x(\d+)\)|\[(\w{4}) m(\w\w) pw(\w\w) x(\d+)\]")
pairs, by_pal, by_flip, singles, zones_with = Counter(), Counter(), Counter(), Counter(), 0
examples = defaultdict(list)
flip = None
total_objs = 0
for path in sys.argv[1:]:
    for line in open(path):
        if line.startswith("flip"):
            flip = int(line.split()[1].rstrip(":"))
            continue
        m = re.match(r"\s*z(\d+) line\s+(\d+) h\s*(\d+) f(\w\w) DL \$(\w+):(.*)", line)
        if not m:
            continue
        z, h, rest = int(m.group(1)), int(m.group(3)), m.group(6)
        wm, objs = 0, []
        for o in OBJ.finditer(rest):
            if o.group(1):
                addr, pw, x, mode = o.group(1), int(o.group(2), 16), int(o.group(3)), None
            else:
                addr, mode, pw, x = o.group(4), int(o.group(5), 16), int(o.group(6), 16), int(o.group(7))
                wm = mode >> 7
            ind = mode is not None and (mode & 0x40)
            total_objs += 1
            objs.append((x, (-pw) & 0x1F or 32, pw >> 5, wm, ind, addr))
        seen = defaultdict(list)
        for i, (x, w, pal, wmo, ind, addr) in enumerate(objs):
            if wmo == 0 and not ind:
                seen[(x, w)].append((i, pal, addr))
        found = False
        for (x, w), lst in seen.items():
            if len(lst) >= 2:
                pals = tuple(sorted(p for i, p, a in lst))
                if len(set(pals)) > 1:
                    pairs[len(lst)] += 1
                    by_pal[pals] += 1
                    by_flip[flip] += 1
                    found = True
                    if len(examples[pals]) < 3:
                        examples[pals].append((flip, z, h, x, w, [a for i, p, a in lst]))
                else:
                    singles[len(lst)] += 1
        zones_with += found
print("objects seen:", total_objs)
print("same x and width, different palettes (merge candidates):", sum(pairs.values()), dict(pairs))
print("same x and width, same palette (not mergeable that way):", sum(singles.values()))
print("zones with a candidate:", zones_with)
print("by palettes:")
for pals, n in by_pal.most_common():
    print("   ", pals, n, "e.g.", examples[pals][:2])
print("candidates by flip:", sorted(by_flip.items()))
