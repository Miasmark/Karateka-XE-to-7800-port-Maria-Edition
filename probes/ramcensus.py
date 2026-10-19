"""The RAM census merged (probes/p7800-ramcensus.lua runs): the addresses no
run wrote after the boot's clear, as runs of at least MIN bytes, each with
the nearest RAM symbol at or below it (work/karateka7800.sym) and, if the
runs logged reads there, whether anything read it.

    python probes/ramcensus.py [MIN] work/analysis/rc-* """
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load(path):
    w, r = set(), set()
    for line in open(path):
        t = line.split()
        if t[0] in ("W", "R") and len(t) == 3:
            page = int(t[1], 16)
            for i, ch in enumerate(t[2]):
                v = int(ch, 16)
                for k in range(4):
                    if v & (8 >> k):
                        (w if t[0] == "W" else r).add(page * 256 + i * 4 + k)
    return w, r


def main():
    args = sys.argv[1:]
    mn = int(args.pop(0)) if args and args[0].isdigit() else 8
    W, R, reads_logged = set(), set(), False
    for d in args:
        p = os.path.join(d, "ramcensus.log")
        if os.path.exists(p):
            w, r = load(p)
            W |= w
            R |= r
            reads_logged |= bool(r)
        else:
            print("(no log in %s)" % d)
    syms = []
    for line in open(os.path.join(HERE, "..", "work", "karateka7800.sym")):
        a, n = line.split()
        if int(a, 16) < 0x8000:
            syms.append((int(a, 16), n))
    syms.sort()

    def near(a):
        best = None
        for s, n in syms:
            if s <= a:
                best = (s, n)
        return "%s+$%X" % (best[1], a - best[0]) if best else "-"
    total = 0
    for lo, hi in ((0x1800, 0x2800), (0x4000, 0x8000)):
        a = lo
        while a < hi:
            if a in W:
                a += 1
                continue
            b = a
            while b < hi and b not in W:
                b += 1
            if b - a >= mn:
                total += b - a
                rd = sum(1 for x in range(a, b) if x in R)
                print("$%04X-$%04X %5d  %-24s%s" % (a, b - 1, b - a, near(a),
                                                     ("  read: %d" % rd) if reads_logged else ""))
            a = b
    print("never written, in runs of %d or more: %d bytes" % (mn, total))


if __name__ == "__main__":
    main()
