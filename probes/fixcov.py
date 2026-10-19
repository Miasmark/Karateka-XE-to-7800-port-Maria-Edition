"""The fixed bank's bytes the CPU never used in these runs (probes/tmp-fixcov.lua's
fixcov.bin, their union): by what the build placed there (work/karateka7800.map),
and in the port's own code by routine (the symbol file); runs of RUN or more
unused bytes listed.
    python probes/fixcov.py [RUN=8] work/analysis/fc-*"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
W = os.path.join(HERE, "..", "work")
args = sys.argv[1:]
RUN = 8
if args and args[0].startswith("RUN="):
    RUN = int(args.pop(0)[4:])
used = bytearray(16384)
for d in args:
    for i, v in enumerate(open(os.path.join(d, "fixcov.bin"), "rb").read()):
        if v:
            used[i] = 1
place = []
cur = None
for ln in open(os.path.join(W, "karateka7800.map")):
    if ln.startswith(";"):
        cur = "F" if "fixed" in ln else None
        continue
    m = re.match(r"\$(\w+)-\$(\w+)\s+(-?\d+)\s+(.*)", ln)
    if cur == "F" and m and int(m.group(3)) > 0:
        place.append((int(m.group(1), 16), int(m.group(1), 16) + int(m.group(3)), m.group(4).strip()))
syms = sorted((int(l.split()[0], 16), l.split()[1]) for l in open(os.path.join(W, "karateka7800.sym"))
              if len(l.split()) == 2 and 0xC000 <= int(l.split()[0], 16) <= 0xFFFF)


def unused(lo, hi):
    return sum(1 for a in range(lo, hi) if not used[a - 0xC000])


print("used %d of 16384" % sum(used))
for lo, hi, what in sorted(place):
    print("%-44s $%04X-$%04X %5d, %5d unused" % (what[:44], lo, hi - 1, hi - lo, unused(lo, hi)))
print("\nthe port's code, by routine (unused bytes):")
for lo, hi, what in sorted(place):
    if "system" not in what:
        continue
    ss = [s for s in syms if lo <= s[0] < hi]
    for k, (a, n) in enumerate(ss):
        e = ss[k + 1][0] if k + 1 < len(ss) else hi
        u = unused(a, e)
        if u >= RUN:
            print("   %04X %-20s %4d bytes, %4d unused" % (a, n, e - a, u))
