"""Console RAM laid out scene by scene, checked by replaying the lists
(FINDINGS "Console RAM: the lists replayed"). From a build's
probes/tmp-ramlive.lua runs (what each scene uses) and probes/tmp-listseq.lua
runs (every rebuild of every row's lists): the CPU's blocks placed first,
best-fit, in bytes no scene uses; then each scene group's four rows (band A,
band B, top A, top B) given runs of the room its scenes leave, the longest
first, till a replay of all the row's rebuilds with every list GROW% longer
places them all (probes/listsim.py's first fit); a run cut to what the row
still needs, the rest back in the pool.
    python probes/consoleplan2.py SYMFILE RAMLIVE_PREFIX LISTSEQ_PREFIX [--write port/consoleplan_out.py]
Environment: TOPL_MAX (the top tables' entries a buffer, default 16)."""
import itertools
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import l1scene7800 as LS                       # noqa: E402

sym = {}
for ln in open(sys.argv[1]):
    p = ln.split()
    if len(p) == 2:
        try:
            sym[p[1]] = int(p[0], 16)
        except ValueError:
            pass
RL, SQ = sys.argv[2], sys.argv[3]
SCENES = (0, 1, 2, 3, 4, 6)
BANK = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 6: 1}
# the scene groups: the group's row (S_BLPC: band A at it, B at it + 8, the
# top's the same), its scenes, the row its scenes' lists were recorded in
# (this build's L1L_BLPC); SPLIT=4 splits levels 2-4 into level 2 and
# levels 3-4 (a new row $30)
GROUPS = {0x20: (0,), 0x00: (1, 6), 0x10: (2, 3, 4)}
if os.environ.get("SPLIT") == "4":
    GROUPS = {0x20: (0,), 0x00: (1, 6), 0x10: (2,), 0x30: (3, 4)}
OLDROW = {0: 0x20, 1: 0x00, 6: 0x00, 2: 0x10, 3: 0x10, 4: 0x10}
GROW = {0x20: int(os.environ.get("GROW20", "7")), 0x00: 10, 0x10: int(os.environ.get("GROW10", "10")), 0x30: 10}           # (the user: about 7% for the attract; the levels more)
LET = {0x00: "A", 0x08: "B", 0x10: "C", 0x18: "D", 0x20: "E", 0x28: "F"}
ZS = set(range(0x2040, 0x2100)) | set(range(0x2140, 0x2200))
ALL = [a for a in range(0x1800, 0x2800) if a not in ZS]
TOPL_MAX = int(os.environ.get("TOPL_MAX", "16"))


def rng(lo, hi):
    return set(range(lo, hi))


# nothing goes here: the DLLs (about 36 entries), the bottom lists, the
# static lists and the NMI's stub, the status lists, DESCBUF's longest
# description (read at a load), the fighters' tables (their capacity: their
# slack fills in heavier fights; they end at $1DAC now, the ZT_BLO/BHI gone)
# SHARE (a what-if, comma list): one copy for both buffers of fo (the
# fighter objects' FO_CELL, FO_X, FO_PW, FO_LO, FO_HB: the fighters' tables
# 160 bytes shorter, FO_HB 40), sort (FS_I and FC_*: 80), status (one
# status list: STATUS_DLB's 76 free); FINDINGS "What in RAM is redundant"
SHARE = set(os.environ.get("SHARE", "").split(","))
# (stsize: each status list STL bytes, 11 objects of 5 and the end, B's
# right after A's; tpdll: TP_DLL the entries' low bytes only, the page the
# buffer's DLL's)
STL = 57
KEEP = (rng(0x2200, 0x2270) | rng(0x2300, 0x2370) | rng(LS.L1BOT, LS.L1BOT + 2 * LS.L1BOT_N)
        | rng(LS.L1BOTB, LS.L1BOTB + 2 * LS.L1BOT_N) | rng(0x2780, 0x27E7)
        | rng(0x1F80, (0x1F80 + STL if "stsize" in SHARE else 0x1FCC) if "status" in SHARE
              else 0x1F80 + 2 * STL if "stsize" in SHARE else 0x2018)
        | rng(0x2018, 0x2040)
        | rng(0x1A2C, 0x1A4E) | rng(0x1B80, 0x1DF6))
# (the small-sprite block's RAM, $1B80-$1DF5, LEN_SPRITES: the fighters' tables in play,
# the text's glyphs whenever text is up, a level's "the end" too, which no
# run reaches. No list or block but the fighters' own: with SHARE fo and
# sort, the sort and FO_HB go after the fighters' tables there, out of
# BLOCKS)
FT_FON = int(os.environ.get("FT_FON", "40"))   # (a what-if: the fighter objects a buffer; the tables
                                               # FO_CELL, FO_X, FO_PW, FO_LO 2 x FT_FON each)
# no block here (lists may be, where the scenes leave it): the text's list
# RAM (the ending's too: no run reaches it), the generator's load scratch,
# $2100-$213F, the system variables (some only in states no run reaches),
# Akuma's tables (the finale's)
GEN_N = sum(n for _, n in LS.GEN_VARS)
NOBLOCK = (rng(0x2410, 0x24E1) | rng(0x2510, 0x2600) | rng(0x2600, 0x2600 + GEN_N) | rng(0x2100, 0x2140)
           | rng(0x1E00, 0x1F00) | rng(0x1AA1, 0x1B4E))
# and no list of levels 2-4's there: Akuma's tables (the finale, scene 4)
NOLIST = {0x10: rng(0x1AA1, 0x1B4E)}
if os.environ.get("NOAKUMA"):                  # (a what-if: levels 2-4 over Akuma's tables)
    NOLIST = {}


def pieces(letters):
    out = set()
    for pre in ("L1S", "TPS"):
        for let in letters:
            for k in range(7):
                lo, hi = sym.get("%s%s%d" % (pre, let, k)), sym.get("%s%s%dE" % (pre, let, k))
                if lo and hi and hi > lo:
                    out |= set(range(lo, hi))
    return out


def load_rl(path):
    t = {}
    for ln in open(path):
        ctx, kind, page, bits = ln.split()
        page = int(page, 16)
        s = t.setdefault(ctx, set())
        for i, ch in enumerate(bits):
            v = int(ch, 16)
            for j in range(4):
                if v & (8 >> j):
                    s.add(page * 256 + 4 * i + j)
    return t


allpieces = pieces("ABCDEF")
# (SHARE: the measured use as the shared layout would have it: fo, the
# B halves of FO_CELL, FO_X, FO_PW, FO_LO gone and what follows them
# moved down 160; status, STATUS_DLB's bytes unused)
OLDFO = sym["FO_X"] - sym["FO_CELL"] == 80         # (the measured build's layout)
OLDST = sym.get("STATUS_DLB", 0) == 0x1FCC
FOB = set()
for t in ("FO_CELL", "FO_X", "FO_PW", "FO_LO"):
    FOB |= rng(sym[t] + 40, sym[t] + 80)


def remap(addrs):
    out = set()
    for a in addrs:
        if "fo" in SHARE and OLDFO and sym["FO_CELL"] <= a < 0x1DAC:
            if a in FOB:
                continue
            a -= sum(1 for b in FOB if b < a)
        if "status" in SHARE and OLDST and (0x1FCC <= a < 0x2018 or ("stsize" in SHARE and 0x1F80 + STL <= a)):
            if a < 0x2018:
                continue
        if "stsize" in SHARE and "status" not in SHARE and OLDST and 0x1F80 <= a < 0x2018:
            i = a - 0x1F80 if a < 0x1FCC else a - 0x1FCC
            if i >= STL:
                continue
            a = 0x1F80 + i + (STL if a >= 0x1FCC else 0)
        out.add(a)
    return out
# and the CPU's reads and writes in the recordings' replays (ROMABLE: their
# tmp-romable.lua folders, comma list: the finale, the real player's play),
# by the scene's bank, counted as play
rec_use = {}
for d in [x for x in os.environ.get("ROMABLE", "").split(",") if x]:
    for ln in open(d + "/romable.log"):
        f = ln.split()
        ad, sc = int(f[0], 16), int(f[1], 16)
        if 0x1800 <= ad < 0x2800 and int(f[2]) + int(f[3]) + int(f[5]) > 0:
            rec_use.setdefault(sc, set()).add(ad)
for k in rec_use:
    rec_use[k] = remap(rec_use[k])
use_pt, use_p, use_l = {}, {}, {}
for s in SCENES:
    t = load_rl("%s%d/ramlive.log" % (RL, s))
    b = "%02X" % BANK[s]
    P, T, Lw = t.get(b + "P", set()), t.get(b + "T", set()), t.get(b + "L", set())
    P, T, Lw = remap(P), remap(T), remap(Lw)
    # (and a load's use: the blocks live through loads, L1VARS drives the
    # generator, the swap buffer and the load's scratch must not meet them)
    use_l[s] = set(Lw)                     # (all of it: the measured build's pieces held the swap
                                           # buffer at loads, $1880-$18FF)
    P |= rec_use.get(BANK[s], set())
    use_pt[s] = {a for a in P | T if a not in allpieces}
    # (scene 0's text rewrites what only it uses: its play lists may share it)
    use_p[s] = {a for a in (P if s == 0 else P | T) if a not in allpieces}

# the rows' rebuilds: (kind, row, scene) -> [(count, [(estimate, real)])],
# the scene the game's ($D0) when it was built
eps = {}
# (LISTSEQ_PREFIX: a prefix with a run a scene, <prefix>0 ... <prefix>6, and,
# after commas, more runs' folders: the recordings' replays)
SQS = SQ.split(",")
for p in ["%s%d/listseq.log" % (SQS[0], s) for s in SCENES] + ["%s/listseq.log" % d for d in SQS[1:]]:
    for ln in open(p):
        f = ln.split()
        n, kind, row, sc = int(f[0]), f[1], int(f[2], 16), int(f[3][1:])
        lists = []
        for t in f[4:]:
            if kind == "band":
                e, r = t.split(":")
                if r != "x":
                    lists.append((max(int(e), int(r)), int(r)))
            else:
                lists.append((int(t), int(t)))
        eps.setdefault((kind, row, sc), []).append((n, lists))


def rebuilds(key):
    """a group's row's rebuilds: (kind, the group's row or row + 8, its scenes)"""
    kind, half, scs = key
    out = []
    for s in scs:
        out += eps.get((kind, OLDROW[s] + half, s), [])
    return out


def grown(lists, g):
    return [(e + (e * g + 99) // 100, r + (r * g + 99) // 100) for e, r in lists]


def fits(key, ps, g):
    for _, lists in rebuilds(key):
        ptr = [lo for lo, _ in ps]
        for e, r in grown(lists, g):
            for k, (lo, hi) in enumerate(ps):
                if ptr[k] + e <= hi:
                    ptr[k] += r
                    break
            else:
                return False
    return True


def need1(key, g):
    m = 0
    for _, lists in rebuilds(key):
        acc = 0
        for e, r in grown(lists, g):
            m = max(m, acc + e)
            acc += r
    return m


def runs(addrs):
    out, r = [], None
    for a in sorted(addrs):
        if r and a == r[1]:
            r[1] = a + 1
        else:
            if r:
                out.append(r)
            r = [a, a + 1]
    if r:
        out.append(r)
    return [tuple(x) for x in out]


# the blocks: the CPU's data now in cart RAM (port/consoleplan_out.py's names)
L1V = sum(n for _, n in LS.RAM_VARS) - int(os.environ.get("L1V_LESS", "0"))   # (a what-if)
BLOCKS = [("SORT", (1 if "sort" in SHARE else 2) * (FT_FON + 40)), ("L1VARS", L1V),
          ("FOHB", (1 if "fo" in SHARE else 2) * FT_FON), ("TPDLL", 20 if "tpdll" in SHARE else 40), ("TPB", 20), ("TOPZA", 20),
          ("TOPZH", 20), ("TOPZT", 5), ("SGV", 17), ("OBJV", 16), ("FTS", 4),
          ("TOPLI", 2 * TOPL_MAX), ("TOPLX", 2 * TOPL_MAX), ("TOPLK0", 2 * TOPL_MAX), ("TOPLK1", 2 * TOPL_MAX),
          ("TOPLS", 6)]
BLOCKS = [b for b in BLOCKS if b[0] not in os.environ.get("ELSEWHERE", "").split(",")]   # (a what-if: kept elsewhere)
if "gram" in SHARE:         # (the game's own data in its framebuffer B, cart RAM: the sound's zero
    BLOCKS += [("GSWAP", 8), ("GSAVE", 16)]   # page swap, XE $3000-$3007; a state save, $47F7-$4806)
if "l1split" in SHARE:      # (level 1's objects' four tables, one block: B's at A's + 2 x L1_NMAX;
    _o = 4 * LS.L1_NMAX     # its other variables in two halves, one clear loop:
    _h = LS.l1var_split()[2]  # l1scene7800's split)
    BLOCKS = [b for b in BLOCKS if b[0] != "L1VARS"] + [("L1VARS", _h), ("L1VARB", _h), ("L1OBJ", _o)]
if "fo" in SHARE and "sort" in SHARE:
    BLOCKS = [b for b in BLOCKS if b[0] not in ("SORT", "FOHB")]
free_all = {a for a in ALL if all(a not in use_pt[s] for s in SCENES) and a not in KEEP}
blockfree = {a for a in free_all if all(a not in use_l[s] for s in SCENES)}
avail = blockfree - NOBLOCK
# each block at an end of a free run: the one inside the shortest run of the
# tightest group's room (TIGHT, default levels 2-4's row $10: their room is in
# few long runs, so blocks go where they cut none of them), then best fit
TIGHT = int(os.environ.get("TIGHT", "16"))
troom = {a for a in ALL if all(a not in use_p[s] for s in GROUPS[TIGHT]) and a not in KEEP
         and a not in NOLIST.get(TIGHT, set())}


def trun(a):
    for lo, hi in runs(troom):
        if lo <= a < hi:
            return hi - lo
    return 0


def place_blocks(rnd):
    """each block at an end of a free run, ranked as below; rnd: a random
    choice among the best three (SEARCH), else the best"""
    av, tr = set(avail), set(troom)

    def trun(at):
        for lo, hi in runs(tr):
            if lo <= at < hi:
                return hi - lo
        return 0
    pl = {}
    for name, size in sorted(BLOCKS, key=lambda b: -b[1]):
        fit = [r for r in runs(av) if r[1] - r[0] >= size]
        if not fit:
            return None
        cands = sorted(set(((trun(at) if os.environ.get("BESTFIT") is None else 0), r[1] - r[0], at)
                           for r in fit for at in (r[0], r[1] - size)))
        _, _, at = rnd.choice(cands[:3]) if rnd else cands[0]
        pl[name] = at
        av -= rng(at, at + size)
        tr -= rng(at, at + size)
    return pl


place = place_blocks(None)
if place is None:
    raise SystemExit("no room for the blocks")
blocks = set()
for name, size in BLOCKS:
    blocks |= rng(place[name], place[name] + size)
print("blocks %d bytes:" % len(blocks), ", ".join("%s $%04X+%d" % (n, place[n], s) for n, s in BLOCKS))
print("free of other use in every scene: %d (less the reservations %d)" % (len(free_all), len(free_all - NOBLOCK)))


def give(key, pool, g):
    """runs from pool (sorted longest first) to key's row till its replay
    passes: a single run that does it, the shortest such, cut to what it
    needs; else the longest, and on"""
    ps = []
    while not fits(key, ps, g):
        if len(ps) == 7 or not pool:
            return None
        one = [r for r in pool if fits(key, ps + [r], g)]
        r = min(one, key=lambda r: r[1] - r[0]) if one else pool[0]
        pool.remove(r)
        if one:
            lo, hi = 16, r[1] - r[0]        # (the shortest prefix that passes, at least 16)
            while lo < hi:
                mid = (lo + hi) // 2
                if fits(key, ps + [(r[0], r[0] + mid)], g):
                    hi = mid
                else:
                    lo = mid + 1
            if r[1] - r[0] - lo >= 16:
                pool.append((r[0] + lo, r[1]))
                pool.sort(key=lambda r: -(r[1] - r[0]))
            r = (r[0], r[0] + lo)
        ps.append(r)
    return ps


def allocate(blocks, verbose):
    plan, ok, lefts = {}, True, {}
    for g, scs in GROUPS.items():
        room = [a for a in ALL if all(a not in use_p[s] for s in scs) and a not in KEEP and a not in blocks
                and a not in NOLIST.get(g, set())]
        keys = [("band", 0, scs), ("band", 8, scs), ("top", 0, scs), ("top", 8, scs)]
        best = None
        for order in itertools.permutations(keys):
            pool = sorted([r for r in runs(room) if r[1] - r[0] >= 16], key=lambda r: -(r[1] - r[0]))
            got = {}
            for key in order:
                ps = give(key, pool, GROW[g])
                if ps is None:
                    break
                got[key] = ps
            else:
                left = sum(r[1] - r[0] for r in pool)
                if best is None or left > best[0]:
                    best = (left, got)
        needs = [need1(k, GROW[g]) for k in keys]
        if best is None:
            ok = False
            if verbose:
                print("group $%02X (scenes %s): room %d in runs %s; one-piece needs %s (sum %d): DOES NOT FIT"
                      % (g, scs, len(room), sorted((r[1] - r[0] for r in runs(room) if r[1] - r[0] >= 16),
                                                   reverse=True), needs, sum(needs)))
            continue
        plan[g] = [best[1][k] for k in keys]
        lefts[g] = best[0]
        if verbose:
            print("group $%02X (scenes %s): room %d, one-piece needs %s (sum %d), left %d"
                  % (g, scs, len(room), needs, sum(needs), best[0]))
            for k, ps in zip(("band A", "band B", "top A", "top B"), plan[g]):
                print("  %s: %s" % (k, ", ".join("$%04X-$%04X" % (a, b - 1) for a, b in sorted(ps))))
    return plan, ok, lefts


def blockset(pl):
    s = set()
    for name, size in BLOCKS:
        s |= rng(pl[name], pl[name] + size)
    return s


plan, ok, lefts = allocate(blocks, False)
# SEARCH=N: placements tried at random among each block's best three, till
# every group fits (the one with the most bytes left in its tightest group)
if not ok and int(os.environ.get("SEARCH", "0")):
    import random
    rnd = random.Random(int(os.environ.get("SEED", "1")))
    bestpl = None
    for it in range(int(os.environ["SEARCH"])):
        pl = place_blocks(rnd)
        if pl is None:
            continue
        p2, ok2, l2 = allocate(blockset(pl), False)
        if ok2 and (bestpl is None or min(l2.values()) > bestpl[0]):
            bestpl = (min(l2.values()), pl)
    if bestpl:
        place = bestpl[1]
        blocks = blockset(place)
        print("search: a placement with %d bytes left in the tightest group" % bestpl[0])
        print("blocks %d bytes:" % len(blocks), ", ".join("%s $%04X+%d" % (n, place[n], s) for n, s in BLOCKS))
plan, ok, lefts = allocate(blocks, True)
print("fits" if ok else "DOES NOT FIT")
if "--write" in sys.argv and ok:
    out = sys.argv[sys.argv.index("--write") + 1]
    with open(out, "w", newline="\n") as f:
        f.write('"""Generated by probes/consoleplan2.py (FINDINGS "Console RAM: the lists\nreplayed"): the CPU\'s'
                ' blocks and each scene group\'s list pieces, in console RAM."""\n')
        f.write("TOPL_MAX = %d\n" % TOPL_MAX)
        for n, s in BLOCKS:
            f.write("%s_AT = 0x%04X       # (%d bytes)\n" % (n, place[n], s))
        for g, rows in plan.items():
            for nm, r in zip(("BAND_A", "BAND_B", "TOP_A", "TOP_B"), rows):
                f.write("G%02X_%s = (%s,)\n" % (g, nm, ", ".join("(0x%04X, 0x%04X)" % (a, b) for a, b in r)))
    print("wrote", out)
