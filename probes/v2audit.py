"""The V2 release audit (FINDINGS "The V2 release audit"): the game data V2
gives back (layout7800 V2_PAGE_RELEASE and V2_CODE_RELEASE, byte by byte
where no scene in the page has an instruction, label or relocation, as
build7800 does) that the code can still reach:
  - an indexed read or write ($nnnn,X / ,Y): its table from the base up to
    the next instruction (at most 256 bytes);
  - a relocated pointer's target (reloc.txt, the census's and the manual
    ones): from the target up to the next instruction or label (at most 64).
Each hit: the scene page, the base or target, who refers to it, and the
released bytes inside. Hits are candidates, to be read by hand: a table can
end before the next instruction.
    V2=1 python probes/v2audit.py
"""
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import layout7800 as L          # noqa: E402
import link7800 as K            # noqa: E402
import xesource as X            # noqa: E402

car = open(K.CAR, "rb").read()
ex = glob.glob(os.path.join(K.ROOT, "census", "*.ex"))
reloc = os.path.join(K.ROOT, "reloc.txt")
models = {s: X.analyse(car, s, ex, reloc) for s in L.SCENES}


def runs(xs):
    out, xs = [], sorted(xs)
    for x in xs:
        if out and x == out[-1][1]:
            out[-1][1] = x + 1
        else:
            out.append([x, x + 1])
    return ", ".join("$%04X-$%04X" % (a, b - 1) for a, b in out)


total = 0
for s in L.PAGE_SCENES:
    here = [t for t in L.SCENES if L.SCENE_BANK[t] == L.SCENE_BANK[s]]
    ms = [models[t] for t in here]
    labs = {v for m in ms for v in m.symbols.values()}
    released = set()
    for lo, hi in L.V2_PAGE_RELEASE.get(s, []) + L.V2_CODE_RELEASE.get(s, []):
        for x in range(lo, hi):
            if not (x in labs or any(x in m.insn or x in m.reloc for m in ms)):
                released.add(x)
    starts = sorted({a for m in ms for a in m.insn})
    import bisect

    def next_code(a, cap):
        i = bisect.bisect_right(starts, a)
        nxt = starts[i] if i < len(starts) else 0x10000
        return min(nxt, a + cap)

    hits = {}
    for t, m in zip(here, ms):
        for pc, (mn, mode, n, opnd) in m.insn.items():
            if mode in ("abx", "aby") and opnd is not None:
                nl = sorted(x for x in labs if x > opnd)          # (to the next label: the next table)
                end = min(next_code(opnd, 256), nl[0] if nl else 0x10000)
                rel = [x for x in range(opnd, end) if x in released]
                if rel:
                    hits.setdefault(("table", opnd), set()).update(rel)
                    hits.setdefault(("table-ref", opnd), set()).add("scene %d $%04X %s" % (t, pc, mn))
        for loc, (kind, v, reg, tg) in m.reloc.items():
            if tg is None:
                continue
            nl = sorted(a for a in labs if a > tg)
            end = min(next_code(tg, 64), nl[0] if nl else 0x10000)
            rel = [x for x in range(tg, end) if x in released]
            if rel:
                hits.setdefault(("pointer", tg), set()).update(rel)
                hits.setdefault(("pointer-ref", tg), set()).add("scene %d $%04X (%s)" % (t, loc, kind))
    print("== scene %d's page (bank %d): %d bytes released" % (s, L.SCENE_BANK[s], len(released)))
    for (k, a), rel in sorted(hits.items(), key=lambda kv: kv[0][1]):
        if k.endswith("-ref"):
            continue
        refs = sorted(hits[(k + "-ref", a)])
        total += 1
        print("  %-7s $%04X: %3d released (%s); from %s" % (k, a, len(rel), runs(rel), "; ".join(refs[:4])
                                                          + (" ..." if len(refs) > 4 else "")))
print("candidates:", total)
