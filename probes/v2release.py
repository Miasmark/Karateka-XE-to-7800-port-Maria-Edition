"""The scene pages' untouched stretches for the new layout's releases
(layout7800 V2_PAGE_RELEASE: the scene data; V2_CODE_RELEASE: the scene code
and common code; FINDINGS "The ROM by scene: step 3"), from
probes/tmp-romuse.lua's runs: each page's bytes no run executed (an opcode
with its operands) or read, in stretches of MIN bytes or more, as XEGS
ranges. And the check: any byte of the layout's tables a run touched.
    python probes/v2release.py CART RUN_DIR... [--min 16] [--banks 0,1,2,3,4]
CART: a cartridge of the runs' layout (the CPU's half; the pages' game
regions are at the same addresses in every build)."""
import argparse
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import layout7800 as L   # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("cart")
ap.add_argument("runs", nargs="+")
ap.add_argument("--min", type=int, default=16)
ap.add_argument("--banks", default="0,1,2,3,4")
ap.add_argument("--write", action="store_true", help="rewrite the two tables in port/layout7800.py")
ap.add_argument("--closure", action="store_true",
                help="keep too what the runs' code reaches untaken: both ways of every branch, JSR and JMP targets")
ap.add_argument("--trim", action="store_true",
                help="the layout's tables less what is kept (the runs' bytes, with --closure the reach too), "
                     "not tables made afresh")
args = ap.parse_args()
CART = open(args.cart, "rb").read()[128:]
LEN1 = {0x00, 0x08, 0x18, 0x28, 0x38, 0x40, 0x48, 0x58, 0x60, 0x68, 0x78, 0x88, 0x8A, 0x98, 0x9A, 0xA8, 0xAA,
        0xB8, 0xBA, 0xC8, 0xCA, 0xD8, 0xE8, 0xEA, 0xF8, 0x0A, 0x2A, 0x4A, 0x6A}


def oplen(op):
    if op in LEN1:
        return 1
    if op in (0x20, 0x4C, 0x6C):
        return 3
    cc, bbb = op & 3, (op >> 2) & 7
    if cc == 1:
        return 3 if bbb in (3, 6, 7) else 2
    return 3 if bbb in (3, 7) else 2


used = defaultdict(set)          # bank -> 7800 addresses touched
exe = defaultdict(set)           # bank (0-4, "F" the fixed one) -> opcodes the runs executed
for d in args.runs:
    for ln in open(os.path.join(d, "romuse.log")):
        bk, ph, sc, kind, page, bits = ln.split()
        if kind == "x" and bk == "F":
            page = int(page, 16)
            for i, ch in enumerate(bits):
                v = int(ch, 16)
                for j in range(4):
                    if v & (8 >> j) and page >= 0xC0:
                        exe["F"].add(page * 256 + 4 * i + j)
            continue
        if kind not in ("x", "r") or bk not in "01234":
            continue
        page = int(page, 16)
        for i, ch in enumerate(bits):
            v = int(ch, 16)
            for j in range(4):
                if v & (8 >> j):
                    a = page * 256 + 4 * i + j
                    n = oplen(CART[int(bk) * 0x4000 + a - 0x8000]) if kind == "x" and a >= 0x8000 else 1
                    if kind == "x" and a >= 0x8000:
                        exe[int(bk)].add(a)
                    for k in range(n):
                        used[int(bk)].add(a + k)

# the NMOS 6502's documented opcodes (the game's code uses no others)
LEGAL = set()
for _row in ("00 01 05 06 08 09 0A 0D 0E 10 11 15 16 18 19 1D 1E 20 21 24 25 26 28 29 2A 2C 2D 2E 30 31 35 36 38 39 3D 3E "
             "40 41 45 46 48 49 4A 4C 4D 4E 50 51 55 56 58 59 5D 5E 60 61 65 66 68 69 6A 6C 6D 6E 70 71 75 76 78 79 7D 7E "
             "81 84 85 86 88 8A 8C 8D 8E 90 91 94 95 96 98 99 9A 9D A0 A1 A2 A4 A5 A6 A8 A9 AA AC AD AE B0 B1 B4 B5 B6 B8 "
             "B9 BA BC BD BE C0 C1 C4 C5 C6 C8 C9 CA CC CD CE D0 D1 D5 D6 D8 D9 DD DE E0 E1 E4 E5 E6 E8 E9 EA EC ED EE "
             "F0 F1 F5 F6 F8 F9 FD FE").split():
    LEGAL.add(int(_row, 16))


def byte(bk, a):
    if bk == "F":
        return CART[7 * 0x4000 + a - 0xC000] if 0xC000 <= a <= 0xFFFF else None
    return CART[bk * 0x4000 + a - 0x8000] if 0x8000 <= a < 0xC000 else None


if args.closure:
    # (from every instruction a run executed: what it can go on to, decoded
    # as the CPU would; a call from the fixed bank into the window into every
    # scene page, as any scene's could be in; the reach's bytes kept as used)
    pages = [int(b) for b in args.banks.split(",")]
    work = [(bk, a) for bk in exe for a in exe[bk]]
    seen = set(work)
    reach = defaultdict(set)
    while work:
        bk, a = work.pop()
        op = byte(bk, a)
        if op is None or op not in LEGAL:
            continue
        n = oplen(op)
        if bk != "F":
            for k in range(n):
                reach[bk].add(a + k)
        nxt = []
        if op not in (0x00, 0x40, 0x60, 0x4C, 0x6C):
            nxt.append(a + n)
        if op & 0x1F == 0x10:                                # a branch: its target too
            o = byte(bk, a + 1)
            if o is not None:
                nxt.append(a + 2 + (o - 256 if o >= 0x80 else o))
        if op in (0x20, 0x4C):
            lo, hi = byte(bk, a + 1), byte(bk, a + 2)
            if lo is not None and hi is not None:
                nxt.append(hi * 256 + lo)
        for t in nxt:
            if t >= 0xC000:
                tos = ["F"]
            elif t >= 0x8000:
                tos = [bk] if bk != "F" else pages
            else:
                tos = []
            for tb in tos:
                if (tb, t) not in seen:
                    seen.add((tb, t))
                    work.append((tb, t))
    for bk in reach:
        more = reach[bk] - used[bk]
        print("bank %s: %d bytes more kept by the code's reach" % (bk, len(more)))
        used[bk] |= reach[bk]

regions = [(rn, rlo, rhi, new) for rn, rlo, rhi, new, where in L.REGIONS if where == "page"]


def to7800(xe):
    return [new + (xe - rlo) for rn, rlo, rhi, new in regions if rlo <= xe < rhi][0]


banks = [int(b) for b in args.banks.split(",")]
tables = {"V2_PAGE_RELEASE": {}, "V2_CODE_RELEASE": {}}
# the check: the layout's released bytes a run touched
for name in ("V2_PAGE_RELEASE", "V2_CODE_RELEASE"):
    tab = getattr(L, name, {})
    for s, rs in sorted(tab.items()):
        bk = L.SCENE_BANK[s]
        hit = [(lo, hi, sorted(a for a in range(to7800(lo), to7800(lo) + hi - lo) if a in used[bk]))
               for lo, hi in rs]
        bad = [(lo, hi, h) for lo, hi, h in hit if h]
        for lo, hi, h in bad:
            print("TOUCHED %s scene %d $%04X-$%04X: %d bytes, first $%04X" % (name, s, lo, hi - 1, len(h), h[0]))
print("(check done)")
# (--trim: the layout's own stretches, less the bytes kept, in what is left of MIN or more)
if args.trim:
    for name in ("V2_PAGE_RELEASE", "V2_CODE_RELEASE"):
        tab = getattr(L, name, {})
        for s, rs in sorted(tab.items()):
            bk = L.SCENE_BANK[s]
            out, was = [], sum(h - l for l, h in rs)
            for lo, hi in rs:
                run = None
                for xe in range(lo, hi + 1):
                    free = xe < hi and to7800(xe) not in used[bk]
                    if free and run is None:
                        run = xe
                    if not free and run is not None:
                        if xe - run >= args.min:
                            out.append((run, xe))
                        run = None
            now = sum(h - l for l, h in out)
            print("%s scene %d: %d bytes in %d stretches (was %d)" % (name, s, now, len(out), was))
            tables[name][s] = out
    banks = []
# the stretches, by region kind
for bk in banks:
    s = [sc for sc, b in sorted(L.SCENE_BANK.items()) if b == bk][0]
    out = {"sdata": [], "code": []}
    for rn, rlo, rhi, new in regions:
        kind = "sdata" if rn == "sdata" else "code"
        run = None
        for xe in range(rlo, rhi + 1):
            free = xe < rhi and (new + xe - rlo) not in used[bk]
            if free and run is None:
                run = xe
            if not free and run is not None:
                if xe - run >= args.min:
                    out[kind].append((run, xe))
                run = None
    for kind in ("sdata", "code"):
        rs = out[kind]
        print("scene %d (bank %d) %s: %d bytes in %d stretches" % (s, bk, kind, sum(h - l for l, h in rs), len(rs)))
        print("    %d: [%s]," % (s, ", ".join("(0x%04X, 0x%04X)" % r for r in rs)))
        tables["V2_PAGE_RELEASE" if kind == "sdata" else "V2_CODE_RELEASE"][s] = rs
if args.write:
    import re
    P = os.path.join(HERE, "..", "port", "layout7800.py")
    src = open(P, encoding="utf-8").read()
    for name, tab in tables.items():
        body = "%s = {\n%s}\n" % (name, "".join("    %d: [%s],\n" % (s, ", ".join("(0x%04X, 0x%04X)" % r for r in rs))
                                                for s, rs in sorted(tab.items())))
        m = re.search(r"^%s = \{\n(?:    .*\n)*\}\n" % name, src, re.M)
        if not m:
            raise SystemExit("%s: not found in layout7800.py" % name)
        src = src[:m.start()] + body + src[m.end():]
    open(P, "w", encoding="utf-8", newline="\n").write(src)
    print("wrote V2_PAGE_RELEASE, V2_CODE_RELEASE to port/layout7800.py")
