"""Every image the game can draw, found statically: the places its code
loads the blitter's source pointer ($03/$04) from split tables (LDA lo,X /
STA $03 ... LDA hi,X / STA $04) or immediates, each table walked entry by
entry, each entry read as an image (rows, width, then rows x width bytes)
in the scene's memory, the $8000 window holding the art bank (14).
Compared with probes/assetinv.py's images.csv (what the runs drew).

    python probes/spritetables.py [work/analysis/assets]

A table's length is bounded by the next address the code refers to after
it (another table), and ends early at the first entry that isn't a
plausible image (rows 1-192, width 1-40, inside one region). Writes
tables.csv and undrawn.csv (images found but never drawn in the runs) to
the folder, and a summary."""
import collections
import csv
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import link7800 as K      # noqa: E402
import xesource as X      # noqa: E402

D = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "work", "analysis", "assets")
car = open(K.CAR, "rb").read()
body = car[16:]
BANK = 0x2000
ex = glob.glob(os.path.join(K.ROOT, "census", "*.ex"))
SCENES = (0, 1, 2, 3, 4, 6)
REGIONS = [(0x0480, 0x1000), (0x1000, 0x3000), (0x6000, 0x8000), (0x8000, 0xA000), (0xA000, 0xC000)]
WINDOW = 14


def region(a):
    for lo, hi in REGIONS:
        if lo <= a < hi:
            return lo, hi
    return None


drawn = {}
for r in csv.DictReader(open(os.path.join(D, "images.csv"))):
    drawn.setdefault((int(r["rows"]), int(r["width"])), []).append(r)
drawn_bytes = set()
# the inventory keeps bytes only in the log; rebuild them from the cartridge copies
for r in csv.DictReader(open(os.path.join(D, "images.csv"))):
    for c in r["cart copies"].split("; "):
        if c:
            b, off = c.split(":")
            b, off = int(b), int(off[1:], 16)
            n = 2 + int(r["rows"]) * int(r["width"])
            drawn_bytes.add(bytes(body[b * BANK + off:b * BANK + off + n]))


def memory(scene):
    sc, segs = X.segments(car, scene)
    mem = {}
    for name, start, data in segs:
        if name == "art":
            data = body[WINDOW * BANK:(WINDOW + 1) * BANK]
        for i, v in enumerate(data):
            mem[start + i] = v
    return sc, mem


def image_at(mem, a):
    if a not in mem or a + 1 not in mem:
        return None
    rows, width = mem[a], mem[a + 1]
    if not (1 <= rows <= 192 and 1 <= width <= 40):
        return None
    rg = region(a)
    n = 2 + rows * width
    if rg is None or a + n > rg[1]:
        return None
    return bytes(mem[a + i] for i in range(n))


def cart_origin(scene, sc, a):
    if 0x8000 <= a < 0xA000:
        return WINDOW, a - 0x8000
    if 0xA000 <= a < 0xC000:
        return 15, a - 0xA000
    if 0x6000 <= a < 0x8000:
        return sc.data_bank, a - 0x6000
    if 0x1000 <= a < 0x3000:
        return sc.code_bank, a - 0x1000
    if 0x0480 <= a < 0x1000:
        return 12, a - 0x0480
    return None


tables = {}          # (lo table, hi table, index reg) -> {"scenes", "sites"}
immediates = collections.defaultdict(set)   # pointer -> {(scene, site)}
unmatched = collections.Counter()
found = {}           # image bytes -> {"at": {(scene, addr)}, "via": set()}
for s in SCENES:
    m = X.analyse(car, s, ex, os.path.join(K.ROOT, "reloc.txt"))
    sc, mem = memory(s)
    pcs = sorted(m.insn)
    order = {pc: i for i, pc in enumerate(pcs)}

    def src_of(pc):
        """The LDA feeding the STA at pc (the instruction before it), as
        (mode, operand)."""
        i = order[pc]
        if i == 0:
            return None
        prev = pcs[i - 1]
        mn, mode, n, opnd = m.insn[prev]
        if prev + n != pc or mn != "LDA":
            return None
        return mode, opnd
    stores = {3: [], 4: []}
    for pc in pcs:
        mn, mode, n, opnd = m.insn[pc]
        if mn == "STA" and mode == "zp" and opnd in (3, 4):
            stores[opnd].append(pc)
    for pc3 in stores[3]:
        s3 = src_of(pc3)
        # the $04 store closest after (within 24 bytes) or before
        near = [p for p in stores[4] if abs(p - pc3) <= 24]
        if not s3 or not near:
            unmatched[(s, pc3)] += 1
            continue
        pc4 = min(near, key=lambda p: abs(p - pc3))
        s4 = src_of(pc4)
        if not s4:
            unmatched[(s, pc3)] += 1
            continue
        (m3, o3), (m4, o4) = s3, s4
        if m3 == "imm" and m4 == "imm":
            immediates[o4 * 256 + o3].add((s, pc3))
        elif m3 in ("abx", "aby") and m4 == m3:
            e = tables.setdefault((o3, o4, m3), {"scenes": set(), "sites": set()})
            e["scenes"].add(s)
            e["sites"].add((s, pc3))
        else:
            unmatched[(s, pc3)] += 1
    # walk the tables for this scene
    refs = sorted(m.refs)
    def bound(t):
        nxt = [r for r in refs if r > t]
        return (nxt[0] - t) if nxt else 64
    for (lo, hi, mode), e in tables.items():
        if s not in e["scenes"]:
            continue
        n = min(bound(lo), bound(hi), 128)
        e.setdefault("entries", {})
        for i in range(n):
            if lo + i not in mem or hi + i not in mem:
                break
            ptr = mem[hi + i] * 256 + mem[lo + i]
            img = image_at(mem, ptr)
            if img is None:
                e["entries"].setdefault(s, []).append((i, ptr, None))
                continue
            e["entries"].setdefault(s, []).append((i, ptr, img))
            f = found.setdefault(img, {"at": set(), "via": set(), "origin": set()})
            f["at"].add((s, ptr))
            f["via"].add("$%04X/$%04X" % (lo, hi))
            f["origin"].add(cart_origin(s, sc, ptr))
    for ptr, sites in immediates.items():
        if any(ss == s for ss, _p in sites):
            img = image_at(mem, ptr)
            if img:
                f = found.setdefault(img, {"at": set(), "via": set(), "origin": set()})
                f["at"].add((s, ptr))
                f["via"].add("immediate")
                f["origin"].add(cart_origin(s, sc, ptr))

with open(os.path.join(D, "tables.csv"), "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["lo", "hi", "index", "scenes", "sites", "entries (scene: index=pointer, * not an image)"])
    for (lo, hi, mode), e in sorted(tables.items()):
        ents = []
        for s, lst in sorted(e.get("entries", {}).items()):
            ents.append("%d: " % s + " ".join("%d=$%04X%s" % (i, p, "" if img else "*") for i, p, img in lst))
        w.writerow(["$%04X" % lo, "$%04X" % hi, mode[-1].upper(), " ".join(map(str, sorted(e["scenes"]))),
                    " ".join("%d:$%04X" % x for x in sorted(e["sites"])), " | ".join(ents)])

undrawn = [(img, f) for img, f in found.items() if img not in drawn_bytes]
with open(os.path.join(D, "undrawn.csv"), "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["rows", "width", "bytes", "at (scene:address)", "cart", "via"])
    for img, f in sorted(undrawn, key=lambda x: sorted(x[1]["at"])):
        w.writerow([img[0], img[1], len(img) - 2, " ".join("%d:$%04X" % x for x in sorted(f["at"])),
                    " ".join("%d:$%04X" % o for o in sorted(o for o in f["origin"] if o)),
                    " ".join(sorted(f["via"]))])
print("pointer tables: %d (lo/hi pairs); immediate pointers: %d; $03 stores not from a table or immediate: %d" % (
    len(tables), len(immediates), len(unmatched)))
print("images found statically: %d, %d bytes; of them drawn in the runs: %d; not drawn: %d, %d bytes" % (
    len(found), sum(len(i) - 2 for i in found), len(found) - len(undrawn), len(undrawn),
    sum(len(i) - 2 for i, _f in undrawn)))
print("drawn in the runs but not found statically: %d" % len(drawn_bytes - set(found)))
