"""The original's graphics inventory, from probes/xe-assetlog.lua's logs:
every image drawn, where it lives in the XEGS cartridge, how much ROM each
scene and each segment (the drawing between two screen clears or loads)
needs, and the identical copies already in the cartridge.

    python probes/assetinv.py work/analysis/as-*  [-o work/analysis/assets]

Writes images.csv (one line per distinct image: content, its cartridge
copies, where it is drawn from, scenes, segments, mirrored), segments.csv
and a summary on stdout.

An image is its bytes: the header (rows, width) and rows x width bytes,
drawn from one address. Where it is drawn from maps to the cartridge by the
XEGS memory map for the loaded scene: $8000-$9FFF the window's bank,
$A000-$BFFF bank 15, $6000-$7FFF the scene's data bank, $1000-$2FFF its code
bank, $0480-$0FFF bank 12 (the common bank); anything else is RAM the game
filled. When the bytes drawn differ from the cartridge's there, the image
was built or changed in RAM ("ram")."""
import argparse
import collections
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import link7800 as K      # noqa: E402
import xesource as X      # noqa: E402

BANK = 0x2000
car = open(K.CAR, "rb").read()
body = car[16:]
NAMES = {0: "title/story", 1: "level 1", 2: "level 2", 3: "level 3", 4: "level 4 (finale)", 5: "scene 5", 6: "gate fight"}


def banks_of(scene):
    sc, _segs = X.segments(car, scene)
    return sc.code_bank, sc.data_bank


BANKS = {s: banks_of(s) for s in (0, 1, 2, 3, 4, 6)}


def origin(scene, src, bank):
    """(cartridge bank, offset in it) of an address, or None for RAM."""
    code, data = BANKS.get(scene, BANKS[0])
    if 0x8000 <= src < 0xA000:
        return (bank, src - 0x8000) if bank >= 0 else None
    if 0xA000 <= src < 0xC000:
        return (15, src - 0xA000)
    if 0x6000 <= src < 0x8000:
        return (data, src - 0x6000)
    if 0x1000 <= src < 0x3000:
        return (code, src - 0x1000)
    if 0x0480 <= src < 0x1000:
        return (12, src - 0x0480)
    return None


def cart_bytes(o, n):
    b, off = o
    if off + n > BANK:
        return None
    return body[b * BANK + off:b * BANK + off + n]


def stored(o, data):
    """The image as the cartridge stores it at o, when the bytes drawn are it
    or its first rows (the game clips by lowering the row count in a RAM
    copy's header: the story scroll's glyphs): (bytes, clipped) or None."""
    if o is None:
        return None
    head = cart_bytes(o, 2)
    if head is None:
        return None
    full = cart_bytes(o, 2 + head[0] * head[1])
    if full is None:
        return None
    if full == data:
        return full, False
    if data[1] == full[1] and data[0] <= full[0] and full[2:].startswith(data[2:]):
        return full, True
    return None


def copies(data):
    """Every place in the cartridge holding these bytes: [(bank, offset)]."""
    out, i = [], body.find(data)
    while i >= 0:
        out.append((i // BANK, i % BANK))
        i = body.find(data, i + 1)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("runs", nargs="+")
    ap.add_argument("-o", "--out", default=os.path.join(HERE, "..", "work", "analysis", "assets"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    content = {}                          # (run, bank, src) -> [bytes versions]
    blits = []                            # (run, frame, scene, seg, kind, src, bank, rows, width)
    marks = collections.defaultdict(list)  # run -> [(frame, what, scene, seg)]
    for run in a.runs:
        name = os.path.basename(run.rstrip("/\\"))
        seg_scene = {}
        for line in open(os.path.join(run, "assetlog.log")):
            p = line.split()
            if p[0] == "B":
                f, sc, sg = int(p[1]), int(p[2]), int(p[3])
                blits.append((name, f, sc, sg, p[4], int(p[5], 16), int(p[6]), int(p[7]), int(p[8]),
                              int(p[9], 16) if len(p) > 9 else -1))
            elif p[0] == "I":
                content.setdefault((name, int(p[1]), int(p[2], 16)), []).append(bytes.fromhex(p[5]))
            elif p[0] == "C":
                marks[name].append((int(p[1]), "clear", int(p[2]), int(p[3])))
            elif p[0] == "L":
                marks[name].append((int(p[1]), "load", int(p[2]), None))

    # each blit's image bytes: the version logged last before or at it (the
    # log writes a version when first seen or changed, in order)
    cur = {}
    img_of = []
    callers_of = []
    versions_seen = collections.Counter()
    for (run, f, sc, sg, kind, src, bank, rows, width, caller) in blits:
        key = (run, bank if 0x8000 <= src < 0xA000 else -1, src)
        vs = content.get(key, [])
        n = 2 + rows * width
        pick = None
        for v in vs:                     # the version matching this size
            if len(v) == n:
                pick = v
        if pick is None:
            continue
        st = stored(origin(sc, src, bank), pick)
        if st:
            pick = st[0]
            if st[1]:
                versions_seen["clipped"] += 1
        img_of.append((run, f, sc, sg, kind, src, bank, pick))
        callers_of.append(caller)

    # distinct images by content
    imgs = {}
    for (run, f, sc, sg, kind, src, bank, data) in img_of:
        e = imgs.setdefault(data, {"from": set(), "scenes": set(), "segs": set(), "kinds": set(), "draws": 0})
        o = origin(sc, src, bank)
        ok = o is not None and cart_bytes(o, len(data)) == data
        e["from"].add((src, o if ok else None))
        e["scenes"].add(sc)
        e["segs"].add((run, sc, sg))
        e["kinds"].add(kind)
        e["draws"] += 1
    for data, e in imgs.items():
        e["copies"] = copies(data)

    # segments: merge the empty ones into the next
    segstat = collections.defaultdict(lambda: {"imgs": set(), "draws": 0, "f0": None, "f1": None})
    for (run, f, sc, sg, kind, src, bank, data) in img_of:
        s = segstat[(run, sc, sg)]
        s["imgs"].add(data)
        s["draws"] += 1
        s["f0"] = f if s["f0"] is None else min(s["f0"], f)
        s["f1"] = f if s["f1"] is None else max(s["f1"], f)

    def size(ds, mirrored_twice=False):
        return sum(len(d) - 2 for d in ds)

    # --- write images.csv
    order = sorted(imgs.items(), key=lambda kv: (min(kv[1]["scenes"]), -len(kv[0])))
    ids = {}
    with open(os.path.join(a.out, "images.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["id", "rows", "width", "bytes", "scenes", "drawn from (XEGS address = cart bank:offset)",
                    "cart copies", "mirrored", "draws", "segments"])
        for i, (data, e) in enumerate(order):
            ids[data] = i
            fr = "; ".join("$%04X=%s" % (src, ("%d:$%04X" % o) if o else "ram") for src, o in sorted(e["from"], key=lambda x: x[0]))
            cp = "; ".join("%d:$%04X" % c for c in e["copies"])
            w.writerow([i, data[0], data[1], len(data) - 2, " ".join(map(str, sorted(e["scenes"]))), fr, cp,
                        "yes" if e["kinds"] & {"M", "MR"} else ("both" if False else "no"),
                        e["draws"], len(e["segs"])])

    # --- segments.csv
    with open(os.path.join(a.out, "segments.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["run", "scene", "seg", "frames", "draws", "images", "bytes", "mirrored images", "image ids"])
        for (run, sc, sg), s in sorted(segstat.items(), key=lambda kv: (kv[0][0], kv[1]["f0"])):
            mir = [d for d in s["imgs"] if imgs[d]["kinds"] & {"M", "MR"}]
            w.writerow([run, sc, sg, "%d-%d" % (s["f0"], s["f1"]), s["draws"], len(s["imgs"]), size(s["imgs"]),
                        len(mir), " ".join(str(ids[d]) for d in sorted(s["imgs"], key=lambda d: ids[d]))])

    # --- callers.csv: the drawing routines, per scene
    per_call = collections.defaultdict(lambda: {"imgs": set(), "draws": 0})
    for (run, f, sc, sg, kind, src, bank, data), caller in zip(img_of, callers_of):
        e = per_call[(sc, caller)]
        e["imgs"].add(data)
        e["draws"] += 1
        imgs[data].setdefault("callers", set()).add(caller)

    def region(c):
        if c < 0:
            return "?"
        if 0x0480 <= c < 0x1000:
            return "common"
        if 0x1000 <= c < 0x1203 or 0x2300 <= c < 0x3000:
            return "engine"
        if 0x1203 <= c < 0x2300:
            return "scene code"
        if 0x6000 <= c < 0x8000:
            return "scene data"
        if 0xA000 <= c < 0xC000:
            return "bank 15"
        return "other"
    with open(os.path.join(a.out, "callers.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["scene", "caller", "region", "draws", "images", "bytes", "mirrored images", "image ids"])
        for (sc, c), e in sorted(per_call.items()):
            mir = [d for d in e["imgs"] if imgs[d]["kinds"] & {"M", "MR"}]
            w.writerow([sc, "$%04X" % c, region(c), e["draws"], len(e["imgs"]), size(e["imgs"]), len(mir),
                        " ".join(str(ids[d]) for d in sorted(e["imgs"], key=lambda d: ids[d]))])

    # --- summary
    print("draws of a clipped copy counted as the stored image: %d" % versions_seen["clipped"])
    print("%d draws logged, %d distinct images, %d bytes of image data (headers not counted)" % (
        len(img_of), len(imgs), size(imgs)))
    unmatched = [d for d, e in imgs.items() if all(o is None for _s, o in e["from"])]
    print("images whose bytes are not the cartridge's where drawn from (built in RAM, or the map is wrong): %d, %d bytes" % (
        len(unmatched), size(unmatched)))
    print()
    per_scene = collections.defaultdict(set)
    for d, e in imgs.items():
        for s in e["scenes"]:
            per_scene[s].add(d)
    print("| scene | images | bytes | mirrored images (bytes) | only this scene (bytes) | shared with others (bytes) |")
    print("|---|---|---|---|---|---|")
    for s in sorted(per_scene):
        ds = per_scene[s]
        mir = [d for d in ds if imgs[d]["kinds"] & {"M", "MR"}]
        only = [d for d in ds if imgs[d]["scenes"] == {s}]
        print("| %d %s | %d | %d | %d (%d) | %d (%d) | %d (%d) |" % (
            s, NAMES.get(s, ""), len(ds), size(ds), len(mir), size(mir), len(only), size(only),
            len(ds) - len(only), size(ds) - size(only)))
    print()
    dup = [(d, e) for d, e in imgs.items() if len(e["copies"]) > 1]
    print("images with more than one copy in the cartridge: %d; the extra copies hold %d bytes" % (
        len(dup), sum((len(e["copies"]) - 1) * len(d) for d, e in dup)))
    multi_from = [(d, e) for d, e in imgs.items() if len({src for src, _o in e["from"]}) > 1]
    print("images drawn from more than one address: %d" % len(multi_from))
    # where the used images sit, by cartridge bank
    bybank = collections.Counter()
    for d, e in imgs.items():
        for src, o in e["from"]:
            if o:
                bybank[o[0]] += len(d)
    print("bytes drawn from each cartridge bank (by the address drawn from; an image drawn from two places counts twice):")
    print("  " + ", ".join("bank %d: %d" % (b, n) for b, n in sorted(bybank.items())))


if __name__ == "__main__":
    main()
