"""The phases of each scene (a room, a cutscene), from probes/assetinv.py's
segments.csv and images.csv: segments of one scene that draw nearly the same
images (Jaccard >= J, default 0.5, against the phase's union) are one phase.
Per phase: the segments and frames, the images and bytes (all of them, and
split by where they live: the art bank, the scene's data bank, its code
bank, the common bank, bank 15), the mirrored bytes, and a snapshot for
naming (xe-assetlog.lua's, the one after the phase's longest segment
started).
    python probes/assetphases.py [work/analysis/assets] [J]"""
import collections
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
D = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "work", "analysis", "assets")
J = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5
ROOT = os.path.dirname(os.path.abspath(D))

img = {}
for r in csv.DictReader(open(os.path.join(D, "images.csv"))):
    frs = [x for x in r["drawn from (XEGS address = cart bank:offset)"].split("; ") if ":" in x]
    fr = frs[0] if frs else "?=ram"          # (the address that matched the cartridge)
    bank = int(fr.split("=")[1].split(":")[0]) if ":" in fr else -1
    img[int(r["id"])] = {"bytes": int(r["bytes"]), "bank": bank, "mir": r["mirrored"] == "yes", "addr": fr.split("=")[0]}
BANKS = {0: (13, 11), 1: (7, 8), 2: (1, 2), 3: (5, 6), 4: (3, 4), 6: (9, 10)}


def where(i, scene):
    b = img[i]["bank"]
    code, data = BANKS[scene]
    if b == 14:
        return "art"
    if b == data:
        return "data"
    if b == code:
        return "code"
    if b == 12:
        return "common"
    if b == 15:
        return "bank 15"
    return "bank %d" % b


segs = []
for r in csv.DictReader(open(os.path.join(D, "segments.csv"))):
    ids = {int(x) for x in r["image ids"].split()} if r["image ids"] else set()
    f0, f1 = map(int, r["frames"].split("-"))
    segs.append({"run": r["run"], "scene": int(r["scene"]), "seg": int(r["seg"]), "f0": f0, "f1": f1,
                 "draws": int(r["draws"]), "ids": ids})

phases = collections.defaultdict(list)          # scene -> [{"ids", "segs"}]
for s in sorted(segs, key=lambda s: -len(s["ids"])):
    if s["draws"] < 20:
        continue                                 # the one-picture transitions: counted in their images only
    best, bj = None, 0.0
    for ph in phases[s["scene"]]:
        u = ph["ids"] | s["ids"]
        j = len(ph["ids"] & s["ids"]) / len(u) if u else 0
        if j > bj:
            best, bj = ph, j
    if best is not None and bj >= J:
        best["ids"] |= s["ids"]
        best["segs"].append(s)
    else:
        phases[s["scene"]].append({"ids": set(s["ids"]), "segs": [s]})

out = []
for sc in sorted(phases):
    for n, ph in enumerate(sorted(phases[sc], key=lambda p: min((s["run"], s["f0"]) for s in p["segs"]))):
        tot = sum(img[i]["bytes"] for i in ph["ids"])
        mir = sum(img[i]["bytes"] for i in ph["ids"] if img[i]["mir"])
        by = collections.Counter()
        for i in ph["ids"]:
            by[where(i, sc)] += img[i]["bytes"]
        long = max(ph["segs"], key=lambda s: s["f1"] - s["f0"])
        snap = os.path.join(ROOT, long["run"], "xegs", "%04d.png" % (long["seg"] - 1))
        runs = collections.Counter(s["run"] for s in ph["segs"])
        out.append((sc, n, len(ph["segs"]), ", ".join("%s x%d" % kv for kv in sorted(runs.items())),
                    "%s %d-%d" % (long["run"], long["f0"], long["f1"]), len(ph["ids"]), tot, mir,
                    "; ".join("%s %d" % kv for kv in by.most_common()), snap))
with open(os.path.join(D, "phases.csv"), "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["scene", "phase", "segments", "runs", "longest", "images", "bytes", "mirrored bytes", "where", "snapshot"])
    for row in out:
        w.writerow(row)
for row in out:
    print("scene %d phase %d: %d segs (%s); longest %s; %d images, %d bytes (%d mirrored); %s" % row[:9])
