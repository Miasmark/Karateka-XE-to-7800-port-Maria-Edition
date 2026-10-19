"""The display lists' pieces against their use (probes/tmp-pieceuse.lua's
logs): each piece (the symbol file's L1SA0-L1SF6, TPSA0-TPSF6, their ...E
ends; rows $00/$08 level 1's A/B, $10/$18 levels 2-4's, $20/$28 scene 0's),
its size and the furthest its allocator's pointer was seen in any run (a
pointer outside its piece is the row's other use: left out).
    python probes/pieceuse.py SYMFILE run_dir..."""
import os
import sys

sym = {}
for ln in open(sys.argv[1]):
    p = ln.split()
    if len(p) == 2:
        try:
            sym[p[1]] = int(p[0], 16)
        except ValueError:
            pass
far = {}
for d in sys.argv[2:]:
    for ln in open(os.path.join(d, "pieceuse.log")):
        kind, row, k, v = ln.split()
        key = (kind, int(row, 16), int(k))
        far.setdefault(key, []).append(int(v, 16))
LET = {0x00: "A", 0x08: "B", 0x10: "C", 0x18: "D", 0x20: "E", 0x28: "F"}
tot = {}
for kind, pre in (("band", "L1S"), ("top", "TPS")):
    for row, let in sorted(LET.items()):
        for k in range(7):
            lo, hi = sym.get("%s%s%d" % (pre, let, k)), sym.get("%s%s%dE" % (pre, let, k))
            if not lo or not hi or hi <= lo:
                continue
            vs = [v for v in far.get((kind, row, k), []) if lo <= v <= hi]
            used = max(vs) - lo if vs else 0
            g = (kind, row >> 4)
            t = tot.setdefault(g, [0, 0])
            t[0] += hi - lo
            t[1] += used
            print("%-4s row $%02X piece %d  $%04X-$%04X %4d bytes, used %4d%s"
                  % (kind, row, k, lo, hi - 1, hi - lo, used, "" if vs else "  (never seen)"))
for (kind, grp), (size, used) in sorted(tot.items()):
    print("%s group %d (both buffers): %d bytes in pieces, %d used at most" % (kind, grp, size, used))
