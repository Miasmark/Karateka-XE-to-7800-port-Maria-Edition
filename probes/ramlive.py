"""Console RAM scene by scene from probes/tmp-ramlive.lua's logs (FINDINGS
"Console RAM laid out scene by scene"). For each scene (its bank's play and
text phases; a load's writes only count if the byte is read later): the
bytes it uses for anything but its own list pieces (its group's, by
L1L_BLPC), what its lists use (pieces MARIA reads or the CPU writes in
play), its room; and the bytes free in every scene (where data every scene
keeps can go). Zero page and the stack left out.
    python probes/ramlive.py SYMFILE RUN_PREFIX [--map]
(the runs <prefix>0, 1, 2, 3, 4, 6)"""
import sys

sym = {}
for ln in open(sys.argv[1]):
    p = ln.split()
    if len(p) == 2:
        try:
            sym[p[1]] = int(p[0], 16)
        except ValueError:
            pass
SCENES = (0, 1, 2, 3, 4, 6)
BANK = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 6: 1}
GROUP = {0: "EF", 1: "AB", 2: "CD", 3: "CD", 4: "CD", 6: "AB"}
ZS = set(range(0x2040, 0x2100)) | set(range(0x2140, 0x2200))
ALL = [a for a in range(0x1800, 0x2800) if a not in ZS]


def pieces(letters):
    out = set()
    for pre in ("L1S", "TPS"):
        for let in letters:
            for k in range(7):
                lo, hi = sym.get("%s%s%d" % (pre, let, k)), sym.get("%s%s%dE" % (pre, let, k))
                if lo and hi and hi > lo:
                    out |= set(range(lo, hi))
    return out


def load(path):
    t = {}
    for ln in open(path):
        ctx, kind, page, bits = ln.split()
        page = int(page, 16)
        s = t.setdefault((ctx, kind), set())
        for i, ch in enumerate(bits):
            v = int(ch, 16)
            for j in range(4):
                if v & (8 >> j):
                    s.add(page * 256 + 4 * i + j)
    return t


nonlist, lists = {}, {}
for s in SCENES:
    t = load("%s%d/ramlive.log" % (sys.argv[2], s))
    b = "%02X" % BANK[s]
    live = set()
    for ph in ("P", "T"):
        for kind in ("r", "w", "m"):
            live |= t.get((b + ph, kind), set())
    # (a load's writes are live when read in play or text; else they are its own scratch)
    pc = pieces(GROUP[s])
    nonlist[s] = {a for a in live if a not in pc and a not in ZS}
    lists[s] = {a for a in live if a in pc}
for s in SCENES:
    free = [a for a in ALL if a not in nonlist[s]]
    print("scene %d: other use %4d, its lists %4d, room %4d (lists' share of it %d%%)"
          % (s, len(nonlist[s]), len(lists[s]), len(free), 100 * len(lists[s]) // max(1, len(free))))
common = [a for a in ALL if all(a not in nonlist[s] for s in SCENES)]
print("free of other use in every scene: %d" % len(common))
if "--map" in sys.argv:
    for row in range(0x1800, 0x2800, 64):
        line = ""
        for a in range(row, row + 64):
            if a in ZS:
                line += "Z"
            else:
                n = sum(1 for s in SCENES if a in nonlist[s])
                line += "." if n == 0 else str(n)
        print("$%04X %s" % (row, line))
