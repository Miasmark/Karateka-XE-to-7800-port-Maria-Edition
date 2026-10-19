"""The port's routines by use (FINDINGS "The ROM by scene: step 2"): each
label of port/sys7800.asm, by the piece it is in (the main block and FAR:
the fixed bank; FARART: the top bank; FARL1, FARL2: level 1's home and
capture banks; FARL0: the generator's bank; FAR04: scene pages 0 and 4;
SCENEPAGE: every scene page; LEVEL1PAGE: level 1's), its bytes to the next
label of the same piece, and whether any run (probes/tmp-romuse.lua's
opcode fetches, in that piece's bank) executed it, in play or text, or only
at loads. Per piece kind: the routines never run, the largest first.
    python probes/romroutines.py SYMFILE RUN_DIR... [--all]"""
import re
import sys
import os
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import layout7800 as L                       # noqa: E402

_skip = {sys.argv.index("--pieces") + 1} if "--pieces" in sys.argv else set()
args = [a for i, a in enumerate(sys.argv) if i and not a.startswith("--") and i not in _skip]
symf, runs = args[0], args[1:]
sym = defaultdict(list)
for ln in open(symf):
    p = ln.split()
    if len(p) == 2:
        try:
            sym[p[1]].append(int(p[0], 16))
        except ValueError:
            pass
BANKS = {"MAIN": ("F",), "FAR": ("F",), "FARART": (str(L.TOP_BANK),), "FARL1": (str(L.L1_HOME),),
         "FARL2": (str(L.L1_CAP),), "FARL0": (str(L.L1_GEN),), "FAR04": ("0", "4"),
         "SCENEPAGE": ("0", "1", "2", "3", "4"), "LEVEL1PAGE": ("1",), "RAMFILL": ()}
kind, piece = "MAIN", "main"
labels = []                              # (kind, piece, name)
for ln in open(os.path.join(HERE, "..", "port", "sys7800.asm"), encoding="utf-8"):
    m = re.match(r"^;;; (FARART|FARL[012]|FAR04|FAR|SCENEPAGE|LEVEL1PAGE|RAMFILL)\b(?: \((\w+)\))?", ln)
    if m:
        kind, piece = m.group(1), m.group(2) or m.group(1)
        continue
    if re.match(r"^;;; END (SCENEPAGE|LEVEL1PAGE|RAMFILL)", ln):
        kind, piece = "MAIN", "main"
        continue
    m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):", ln)
    if m:
        labels.append((kind, piece, m.group(1)))
x = defaultdict(lambda: defaultdict(set))       # bank -> addr -> {phase}
for d in runs:
    for ln in open(d + "/romuse.log"):
        bk, ph, sc, k, page, bits = ln.split()
        if k != "x":
            continue
        page = int(page, 16)
        for i, ch in enumerate(bits):
            v = int(ch, 16)
            for j in range(4):
                if v & (8 >> j):
                    x[bk][page * 256 + 4 * i + j].add((ph, int(sc)))
# each label's address (the one the symbol file has: a label twice in the
# symbol file, in two banks, is ambiguous: its first), its piece's order
bypiece = defaultdict(list)
for k, pc, nm in labels:
    if sym.get(nm):
        bypiece[(k, pc)].append((sym[nm][0], nm))
rows = []
for (k, pc), ls in bypiece.items():
    ls.sort()
    for i, (a, nm) in enumerate(ls):
        nxt = ls[i + 1][0] if i + 1 < len(ls) else a + 1
        n = max(1, nxt - a)
        if n > 2048:
            n = 1
        phs = set()
        for bk in BANKS.get(k, ()):
            for ad in range(a, a + n):
                phs |= x[bk].get(ad, set())
        play = {s for p, s in phs if p in ("P", "T")}
        cls = "play" if play else ("load" if phs else "never")
        rows.append((k, pc, nm, a, n, cls, play))
tot = defaultdict(lambda: defaultdict(int))
for k, pc, nm, a, n, cls, play in rows:
    tot[k][cls] += n
print("bytes by piece kind (to the next label): play, load only, never")
for k in sorted(tot):
    print("  %-10s %6d %6d %6d" % (k, tot[k]["play"], tot[k]["load"], tot[k]["never"]))
# per piece: bytes run in play by more than one scene, by one (which),
# only at loads, never (--pieces KIND)
if "--pieces" in sys.argv:
    want = sys.argv[sys.argv.index("--pieces") + 1]
    agg = defaultdict(lambda: defaultdict(int))
    for k, pc, nm, a, n, cls, play in rows:
        if k != want:
            continue
        c = cls if cls != "play" else ("shared" if len(play) > 1 else "scene %d" % min(play))
        agg[pc][c] += n
    print("\n%s pieces: shared, one scene (which), loads only, never" % want)
    for pc, d in sorted(agg.items(), key=lambda kv: -sum(kv[1].values())):
        one = {c: v for c, v in d.items() if c.startswith("scene")}
        print("  %-14s %6d %6d %6d %6d  %s" % (pc, d.get("shared", 0), sum(one.values()), d.get("load", 0),
                                            d.get("never", 0), " ".join("%s:%d" % (c[6:], v) for c, v in sorted(one.items()))))
    sys.exit(0)
for k in sorted(tot):
    nev = sorted((r for r in rows if r[0] == k and r[5] == "never"), key=lambda r: -r[4])
    print("\n%s: never run, the largest (piece, label, address, bytes):" % k)
    for r in nev[:40 if "--all" not in sys.argv else None]:
        print("  %-14s %-16s $%04X %5d" % (r[1], r[2], r[3], r[4]))
