"""Bank 5's code run in play (p7800-wincode.lua logs), by the sys7800.asm
FARART section and label it falls in; the sections' sizes from the symbol
file. python probes/b5code.py work/analysis/wc-s1 ..."""
import re
import sys
from collections import defaultdict

src = open("port/sys7800.asm", encoding="utf-8").read().splitlines()
section_of = {}
sec = None
for ln in src:
    m = re.match(r";;; (FARART|FAR|ALLPAGES|SCENEPAGE|LEVEL1PAGE|RAMFILL|PART|END)\b(?: \(([^)]*)\))?", ln)
    if m:
        sec = ("FARART " + (m.group(2) or "?")) if m.group(1) == "FARART" else None
        continue
    m = re.match(r"([A-Za-z_][A-Za-z0-9_]*):", ln)
    if m and sec:
        section_of[m.group(1)] = sec
addr = {}
for ln in open("work/karateka7800.sym"):
    p = ln.split()
    if len(p) == 2 and p[1] in section_of:
        addr[p[1]] = int(p[0], 16)
labels = sorted((a, n) for n, a in addr.items())

def label_at(a):
    best = None
    for la, n in labels:
        if la <= a:
            best = n
        else:
            break
    return best

run = defaultdict(set)
fetch = defaultdict(int)
for d in sys.argv[1:]:
    for ln in open(d + "/wincode.log"):
        b, a, n = ln.split()
        if int(b) != 5:
            continue
        a = int(a, 16)
        lab = label_at(a)
        sec = section_of.get(lab, "?") if lab else "?"
        for k in range(3):
            run[sec].add(a + k)
        fetch[sec] += int(n)
# a section's size: from its first label to the next section's first label
first = {}
for la, n in labels:
    s = section_of[n]
    first[s] = min(first.get(s, 1 << 20), la)
order = sorted(first.items(), key=lambda kv: kv[1])
size = {}
for i, (s, a) in enumerate(order):
    nxt = order[i + 1][1] if i + 1 < len(order) else 0xC000
    size[s] = nxt - a
tot = sum(fetch.values())
print("%-28s %6s %8s %7s" % ("section", "size", "run", "fetches"))
for s in sorted(run, key=lambda s: -fetch[s]):
    print("%-28s %6s %8d %6.1f%%" % (s, size.get(s, "?"), len(run[s]), 100 * fetch[s] / tot))
print("run in all: %d bytes" % sum(len(v) for v in run.values()))
