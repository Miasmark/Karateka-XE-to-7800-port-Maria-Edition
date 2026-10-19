"""Console RAM laid out scene by scene (FINDINGS "Console RAM laid out scene
by scene"): from probes/tmp-ramlive.lua's runs on a build, where the CPU's
data blocks now in cart RAM go (bytes no scene uses in play or text but as
list pieces, less what must stay free: the DLLs' room, the bottom lists, the
static lists and the NMI's stub, the text's list RAM, the generator's load
scratch), then each scene group's list pieces in the room its scenes leave
(their play; scene 0's text rewrites what only it uses, so its play lists
may share it), a row's pieces at most 7, the largest first.
    python probes/consoleplan.py SYMFILE RUN_PREFIX [--write port/consoleplan_out.py]"""
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
PRE = sys.argv[2]
SCENES = (0, 1, 2, 3, 4, 6)
BANK = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 6: 1}
GROUPS = {0x20: (0,), 0x00: (1, 6), 0x10: (2, 3, 4)}
OLDLET = {0x20: "EF", 0x00: "AB", 0x10: "CD"}    # (the groups' rows' letters in this build)
ZS = set(range(0x2040, 0x2100)) | set(range(0x2140, 0x2200))
ALL = [a for a in range(0x1800, 0x2800) if a not in ZS]


def rng(lo, hi):
    return set(range(lo, hi))


# what stays free of both: the DLLs' room (about 36 entries), the bottom
# lists (L1BOT_N a zone, two zones a buffer), the static lists and the NMI's
# stub (SMALLDL_AT on: their code's operands aren't data reads)
KEEP = (rng(0x2200, 0x2270) | rng(0x2300, 0x2370) | rng(LS.L1BOT, LS.L1BOT + 2 * LS.L1BOT_N)
        | rng(LS.L1BOTB, LS.L1BOTB + 2 * LS.L1BOT_N) | rng(0x2780, 0x27E7)
        | rng(0x1F80, 0x2040)                  # (the status lists: their length varies)
        | rng(0x1A2C, 0x1A4E)                  # (DESCBUF's descriptions, read when a DLL is built:
                                               # at a load too, under the blank list; the longest ends
                                               # at $1A4D)
        | rng(0x1B80, 0x1DF6))                 # (the fighters' tables and the game's sprite
                                               # region: their slack fills in heavier fights)
# and from the blocks: the text's list RAM (the ending's too: no scripted run
# reaches it) and the generator's scratch (written at each load)
GEN_N = sum(n for _, n in LS.GEN_VARS)
KEEP_BLOCKS = (KEEP | rng(0x2410, 0x24E1) | rng(0x2510, 0x2600) | rng(0x2600, 0x2600 + GEN_N) | rng(0x2100, 0x2140)
               | rng(0x1E00, 0x1F00)           # (the system variables: some only in states no run reaches)
               | rng(0x1AA1, 0x1B80))          # (Akuma's tables: the finale's)


def pieces(letters):
    out = set()
    for pre in ("L1S", "TPS"):
        for let in letters:
            for k in range(7):
                lo, hi = sym.get("%s%s%d" % (pre, let, k)), sym.get("%s%s%dE" % (pre, let, k))
                if lo and hi and hi > lo:
                    out |= set(range(lo, hi))
    return out


def rows_of(letters):
    out = []
    for pre, let in (("L1S", letters[0]), ("L1S", letters[1]), ("TPS", letters[0]), ("TPS", letters[1])):
        s = set()
        for k in range(7):
            lo, hi = sym.get("%s%s%d" % (pre, let, k)), sym.get("%s%s%dE" % (pre, let, k))
            if lo and hi and hi > lo:
                s |= set(range(lo, hi))
        out.append(s)
    return out


def load(path):
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


use_pt, use_p, need = {}, {}, {}
for s in SCENES:
    t = load("%s%d/ramlive.log" % (PRE, s))
    b = "%02X" % BANK[s]
    g = [k for k, v in GROUPS.items() if s in v][0]
    pc = pieces(OLDLET[g])
    P, T = t.get(b + "P", set()), t.get(b + "T", set())
    use_pt[s] = {a for a in P | T if a not in pc}
    use_p[s] = {a for a in (P if s == 0 else P | T) if a not in pc}
    rows = rows_of(OLDLET[g])
    need[s] = [len(P & r) for r in rows]
# the blocks (port/consoleplan_out.py's names): size, alignment of halves
# (the sort's halves at +0 and +FS_BOFF 80: 160; the TP_* group's DLL
# entries apart from its bytes; the slots' zones, row and height apart;
# HYBRID: the top tables and FO_HB stay in cart RAM)
BLOCKS = [("SORT", 160), ("L1VARS", sum(n for _, n in LS.RAM_VARS)), ("TPDLL", 40), ("TPB", 20),
          ("TOPZA", 20), ("TOPZH", 20), ("TOPZT", 5), ("SGV", 17), ("OBJV", 16), ("FTS", 4)]
if not os.environ.get("HYBRID"):
    BLOCKS += [("TOPLI", 56), ("TOPLX", 56), ("TOPLK0", 56), ("TOPLK1", 56), ("TOPLS", 6), ("FOHB", 80)]
free_all = [a for a in ALL if all(a not in use_pt[s] for s in SCENES) and a not in KEEP_BLOCKS]


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
    return out


avail = set(free_all)
place = {}
for name, size in sorted(BLOCKS, key=lambda b: -b[1]):
    fit = [r for r in runs(avail) if r[1] - r[0] >= size]
    if not fit:
        raise SystemExit("no room for block %s (%d bytes); free runs %s" % (name, size, [(hex(r[0]), r[1] - r[0]) for r in runs(avail)][:12]))
    r = min(fit, key=lambda r: r[1] - r[0])
    place[name] = r[0]
    avail -= set(range(r[0], r[0] + size))
blocks = set()
for name, size in BLOCKS:
    blocks |= set(range(place[name], place[name] + size))
print("blocks:", ", ".join("%s $%04X+%d" % (n, place[n], s) for n, s in BLOCKS))
print("free everywhere for blocks: %d; blocks take %d" % (len(free_all), len(blocks)))
MARGIN = {0x20: 1.06, 0x00: 1.15, 0x10: 1.12}     # (the attract's demo the same each loop: its peak known)
# (band rows: the allocator takes a piece only with room for its estimate
# of a list, more than the bytes it then writes: levels 2-4 dropped a zone
# at 1.15; their room allows more)
BAND_MARGIN = {0x20: 1.06, 0x00: 1.15, 0x10: 1.15}
# the rows' peaks (band A, band B, top A, top B): the allocators' pointers
# summed per row in one frame (probes/tmp-pieceuse.lua, on the roomy layout
# of 2026-10-15_KEEP_enh-nofrontboxes, every scene, the scene check's
# lengths). The bytes touched (tmp-ramlive.lua) undercount them: a list
# takes its estimate's room when placed, and level 2's buffer B held 407
PEAK = {0x20: (411, 411, 116, 116), 0x00: (308, 302, 116, 116), 0x10: (401, 407, 166, 166)}
TOPMIN, BANDMIN = 64, 96
plan = {}
ok = True
for g, scs in GROUPS.items():
    room = [a for a in ALL if all(a not in use_p[s] for s in scs) and a not in KEEP and a not in blocks]
    tgt = [int(PEAK[g][i] * (BAND_MARGIN[g] if i < 2 else MARGIN[g])) + 1 for i in range(4)]
    rs = sorted([r for r in runs(room) if r[1] - r[0] >= 16], key=lambda r: -(r[1] - r[0]))
    rows = [[], [], [], []]
    got = [0, 0, 0, 0]
    # each row its longest piece first (band rows, then top rows), then by the
    # largest remaining shortfall
    for i, mn in ((0, BANDMIN), (1, BANDMIN), (2, TOPMIN), (3, TOPMIN)):
        r = next((r for r in rs if r[1] - r[0] >= mn), None)
        if r is None:
            print("group $%02X row %d: no run of %d" % (g, i, mn))
            ok = False
            continue
        take = min(r[1] - r[0], tgt[i])
        rows[i].append((r[0], r[0] + take))
        got[i] += take
        rs.remove(r)
        if r[1] - r[0] > take:
            rs.append([r[0] + take, r[1]])
            rs.sort(key=lambda r: -(r[1] - r[0]))
    while rs:
        short = [(tgt[i] - got[i], i) for i in range(4) if got[i] < tgt[i] and len(rows[i]) < 7]
        if not short:
            break
        d, i = max(short)
        r = rs.pop(0)
        if r[1] - r[0] < 16:
            break
        take = min(r[1] - r[0], max(d, 16))     # (no piece under 16 bytes)
        if r[1] - r[0] - take < 16:
            take = r[1] - r[0]
        rows[i].append((r[0], r[0] + take))
        got[i] += take
        if r[1] - r[0] - take >= 16:
            rs.append([r[0] + take, r[1]])
            rs.sort(key=lambda r: -(r[1] - r[0]))
    left = sum(r[1] - r[0] for r in rs)
    print("group $%02X (scenes %s): room %d, targets %s, got %s, left %d" % (g, scs, len(room), tgt, got, left))
    if any(got[i] < tgt[i] for i in range(4)):
        ok = False
    plan[g] = rows
for g, rows in plan.items():
    for nm, r in zip(("band A", "band B", "top A", "top B"), rows):
        print("  $%02X %s: %s" % (g, nm, ", ".join("$%04X-$%04X" % (a, b - 1) for a, b in sorted(r))))
print("fits" if ok else "DOES NOT FIT")
if "--write" in sys.argv and ok:
    out = sys.argv[sys.argv.index("--write") + 1]
    with open(out, "w", newline="\n") as f:
        f.write('"""Generated by probes/consoleplan.py (FINDINGS "Console RAM laid out scene\nby scene"): the CPU\'s blocks and each scene group\'s list pieces."""\n')
        for n, s in BLOCKS:
            f.write("%s_AT = 0x%04X       # (%d bytes)\n" % (n, place[n], s))
        for g, rows in plan.items():
            for nm, r in zip(("BAND_A", "BAND_B", "TOP_A", "TOP_B"), rows):
                f.write("G%02X_%s = (%s,)\n" % (g, nm, ", ".join("(0x%04X, 0x%04X)" % (a, b) for a, b in sorted(r, key=lambda r: r[1] - r[0]))))
    print("wrote", out)
