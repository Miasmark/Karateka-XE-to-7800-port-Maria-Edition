"""Console RAM scene by scene (FINDINGS "Console RAM laid out scene by
scene"): from each scene's own runs (tmp-romable.lua's romable.log: the
CPU's reads and writes after the boot's clear, by the scene's bank; and
p7800-ramclass.lua's ramclass.log: MARIA's lists and graphics), which bytes
each scene uses for anything but its list pieces (its group's: S_BLPC by
L1L_BLPC), and so:
  - each scene's room for its lists (the bytes it leaves), against what its
    lists use now (the pieces' bytes MARIA read);
  - the bytes no scene uses but as list pieces: room the lists could give
    the cart RAM's CPU data.
Zero page and the stack are left out. The title's frames (scene key 00 in
a level's run, before its injection) count as scene 0's.
    python probes/sceneroom.py SYMFILE RG_PREFIX RF_PREFIX
(the run folders: <prefix>0, 1, 2, 3, 4, 6)"""
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
GROUP = {0: "EF", 1: "AB", 2: "CD", 3: "CD", 4: "CD", 6: "AB"}     # (L1L_BLPC $20, $00, $10)
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


def maria(path):
    s = set()
    for ln in open(path):
        k, page, bits = ln.split()
        if k not in "LDG":
            continue
        page = int(page, 16)
        for i, ch in enumerate(bits):
            v = int(ch, 16)
            for j in range(4):
                if v & (8 >> j):
                    s.add(page * 256 + 4 * i + j)
    return s


use = {s: set() for s in SCENES}          # (non-piece use, by scene)
lists = {s: set() for s in SCENES}        # (its pieces' bytes MARIA read)
for s in SCENES:
    pc = pieces(GROUP[s])
    cpu = {}
    for ln in open("%s%d/romable.log" % (sys.argv[2], s)):
        p = ln.split()
        a, key = int(p[0], 16), int(p[1], 16)
        cpu.setdefault(key, set()).add(a)
    mine = cpu.get(BANK[s], set())
    title = cpu.get(0, set()) if s != 0 else set()
    m = maria("%s%d/ramclass.log" % (sys.argv[3], s))
    use[s] |= {a for a in mine if a not in pc}
    use[s] |= {a for a in m if a not in pc}
    lists[s] |= {a for a in m if a in pc}
    if s != 0:
        use[0] |= title                   # (the title's frames before the injection)
for s in SCENES:
    room = len([a for a in ALL if a not in use[s]])
    print("scene %d: uses %4d bytes for other things, leaves %4d; its lists' pieces read %4d"
          % (s, len([a for a in ALL if a in use[s]]), room, len(lists[s])))
free = [a for a in ALL if all(a not in use[s] for s in SCENES)]
print("bytes no scene uses but as list pieces: %d" % len(free))
runs, run = [], None
for a in ALL + [None]:
    if a is not None and a in free and (run is None or a == run[1] + 1):
        run = [run[0] if run else a, a]
        continue
    if run:
        runs.append(run)
    run = [a, a] if (a is not None and a in free) else None
for lo, hi in runs:
    if hi - lo + 1 >= 16:
        print("  $%04X-$%04X %d" % (lo, hi, hi - lo + 1))
