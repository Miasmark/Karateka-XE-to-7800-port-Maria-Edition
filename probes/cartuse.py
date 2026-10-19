"""Cart RAM under BankSet's RAM rules (FINDINGS "BankSet: the CPU off cart
RAM"): p7800-ramclass.lua runs (LO=4000 HI=7FFF NOREAD=1: MARIA's lists,
graphics, the CPU's writes) merged with p7800-cpureads.lua runs (the CPU's
data reads, stores left out; instruction fetches). Per page: bytes MARIA
reads as lists and as graphics, bytes the CPU writes, bytes it reads (and
its readers, by the symbol before each PC).
    python probes/cartuse.py SYM "ramclass dirs" "cpureads dirs" """
import bisect
import collections
import glob
import sys

STORE = {0x81, 0x85, 0x8D, 0x91, 0x95, 0x99, 0x9D, 0x84, 0x8C, 0x94, 0x86, 0x8E, 0x96}
syms = []
for ln in open(sys.argv[1]):
    a, n = ln.split()
    syms.append((int(a, 16), n))
syms.sort()
keys = [a for a, n in syms]


def name(pc):
    i = bisect.bisect_right(keys, pc) - 1
    return "%s+%d" % (syms[i][1], pc - syms[i][0]) if i >= 0 else "%04X" % pc


cls = collections.defaultdict(set)
for d in glob.glob(sys.argv[2]):
    for ln in open(d + "/ramclass.log"):
        k, page, bits = ln.split()
        page = int(page, 16)
        for i, ch in enumerate(bits):
            v = int(ch, 16)
            for j in range(4):
                if v & (8 >> j):
                    cls[page * 256 + 4 * i + j].add(k)
reads = collections.defaultdict(collections.Counter)
code = collections.Counter()
for d in glob.glob(sys.argv[3]):
    for ln in open(d + "/cpureads.log"):
        p = ln.split()
        if p[0] == "code":
            code[int(p[1], 16)] += int(p[2])
            continue
        page, where, op, n = int(p[1], 16), p[2], int(p[3], 16), int(p[4])
        if op in STORE:
            continue
        w, pc = where.split(":")
        reads[page]["%s%s" % ("" if w in ("F", "R") else w + ":", name(int(pc, 16)))] += n
print("page  lists graphics written | CPU reads (readers)")
for page in range(0x40, 0x80):
    a = range(page * 256, page * 256 + 256)
    l = sum(1 for x in a if cls[x] & {"L", "D"})
    g = sum(1 for x in a if "G" in cls[x])
    w = sum(1 for x in a if "W" in cls[x])
    r = reads.get(page)
    if not (l or g or w or r or code.get(page)):
        continue
    rs = ", ".join("%s" % k for k, n in r.most_common(5)) if r else ""
    print("$%02X  %5d %8d %7d | %s%s" % (page, l, g, w, "CODE  " if code.get(page) else "", rs))
