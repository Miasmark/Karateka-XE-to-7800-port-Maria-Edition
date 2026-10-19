"""The RAM census by mode merged (probes/p7800-ramcensus2.lua runs): RAM
gameplay neither writes nor reads (free while a level plays, if the title and
story set up their own uses again), the part of it the title, story and demo
use, and the column-shaped blocks in it (the same offsets free in at least
MINPAGES consecutive pages: what a multi-line zone's graphics need).

    python probes/ramcensus2.py [MINPAGES] work/analysis/r2-* """
import os
import sys


def load(path):
    sets = {"G": set(), "N": set(), "R": set()}
    for line in open(path):
        t = line.split()
        if t[0] in sets and len(t) == 3:
            page = int(t[1], 16)
            for i, ch in enumerate(t[2]):
                v = int(ch, 16)
                for k in range(4):
                    if v & (8 >> k):
                        sets[t[0]].add(page * 256 + i * 4 + k)
    return sets


def runs(addrs, lo, hi, mn):
    out, a = [], lo
    while a < hi:
        if a not in addrs:
            a += 1
            continue
        b = a
        while b < hi and b in addrs:
            b += 1
        if b - a >= mn:
            out.append((a, b))
        a = b
    return out


def main():
    args = sys.argv[1:]
    minpages = int(args.pop(0)) if args and args[0].isdigit() else 16
    G, N, R = set(), set(), set()
    for d in args:
        p = os.path.join(d, "ramcensus2.log")
        if not os.path.exists(p):
            print("(no log in %s)" % d)
            continue
        s = load(p)
        G |= s["G"]; N |= s["N"]; R |= s["R"]
    ram = [a for lo, hi in ((0x1800, 0x2800), (0x4000, 0x8000)) for a in range(lo, hi)]
    free = {a for a in ram if a not in G and a not in R}
    attract_only = {a for a in free if a in N}
    print("gameplay neither writes nor reads: %d bytes; of them the title/story/demo write %d"
          % (len(free), len(attract_only)))
    print("\nruns of 32 or more free in gameplay (n = written by the title/story/demo):")
    for lo, hi in ((0x1800, 0x2800), (0x4000, 0x8000)):
        for a, b in runs(free, lo, hi, 32):
            nn = sum(1 for x in range(a, b) if x in N)
            print("  $%04X-$%04X %5d%s" % (a, b - 1, b - a, ("   n %d" % nn) if nn else ""))
    # column-shaped blocks: greedy, widest first, over pages in each RAM area
    print("\ncolumn blocks free in gameplay (offsets x pages, at least %d pages):" % minpages)
    taken = set()
    total = 0
    for plo, phi in ((0x18, 0x28), (0x40, 0x80)):
        while True:
            best = None
            for o0 in range(256):
                for p0 in range(plo, phi):
                    # the longest run of pages from p0 with offset o0 free
                    p1 = p0
                    while p1 < phi and (p1 * 256 + o0) in free and (p1 * 256 + o0) not in taken:
                        p1 += 1
                    if p1 - p0 < minpages:
                        continue
                    # widen while every page in p0..p1 stays free
                    o1 = o0
                    while o1 < 256 and all((p * 256 + o1) in free and (p * 256 + o1) not in taken
                                           for p in range(p0, p1)):
                        o1 += 1
                    area = (o1 - o0) * (p1 - p0)
                    if best is None or area > best[0]:
                        best = (area, o0, o1, p0, p1)
            if best is None or best[0] < 64:
                break
            area, o0, o1, p0, p1 = best
            for p in range(p0, p1):
                for o in range(o0, o1):
                    taken.add(p * 256 + o)
            total += area
            nn = sum(1 for p in range(p0, p1) for o in range(o0, o1) if (p * 256 + o) in N)
            print("  offsets $%02X-$%02X x pages $%02X-$%02X: %d bytes (%d wide, %d pages)%s"
                  % (o0, o1 - 1, p0, p1 - 1, area, o1 - o0, p1 - p0, ("   n %d" % nn) if nn else ""))
    print("column-shaped in all: %d bytes" % total)


if __name__ == "__main__":
    main()
