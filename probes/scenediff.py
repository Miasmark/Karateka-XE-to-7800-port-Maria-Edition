"""The sites where two scenes' banks differ (the vs fight, scene 6, is
level 1's banks patched): each differing range of the code bank ($1000-
$2FFF) and the data bank ($6000-$7FFF), both scenes' disassembly around it
(from MARGIN bytes before, so the instruction stream lines up), the lines
that differ.
    python probes/scenediff.py [A B]          (default: scenes 1 and 6)"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import dis as D   # noqa: E402

MARGIN, JOIN = 12, 8
a, b = (int(x) for x in sys.argv[1:3]) if len(sys.argv) > 2 else (1, 6)
ma, mb = D.memory(a), D.memory(b)


def ranges(lo, hi):
    out, i = [], lo
    while i < hi:
        if ma[i] != mb[i]:
            j = i
            while j < hi and any(ma[k] != mb[k] for k in range(j, min(hi, j + JOIN))):
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


def lines(m, lo, hi):
    pc, out = lo, []
    while pc < hi:
        n, t = D.line(m, pc)
        out.append(t)
        pc += n
    return out


n = 0
for lo, hi in ((0x1000, 0x3000), (0x6000, 0x8000)):
    for s, e in ranges(lo, hi):
        n += 1
        la, lb = lines(ma, s - MARGIN, e + 4), lines(mb, s - MARGIN, e + 4)
        sa, sb = set(la), set(lb)
        print("== %d. $%04X-$%04X (%d bytes)" % (n, s, e - 1, e - s))
        for t in la:
            if t not in sb:
                print("  %d: %s" % (a, t))
        for t in lb:
            if t not in sa:
                print("  %d: %s" % (b, t))
