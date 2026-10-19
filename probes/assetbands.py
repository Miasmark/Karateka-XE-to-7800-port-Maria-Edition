"""Where on the screen each drawing routine draws, from probes/xe-assetlog.lua's
logs (with the $05/$06 fields): per scene and caller, the buffer rows its
images cover ($06 - 35 down, rows of the image), as the full range and the
range holding 98% of the drawn rows, how often it draws mirrored and from
the fighters' art bank; and the fills' rows. For choosing MARIA zones.

    python probes/assetbands.py work/analysis/as-*"""
import collections
import sys

ROW0 = 35                                   # $06 of buffer row 0 ($2D46)
runs = sys.argv[1:]
rows = collections.defaultdict(collections.Counter)    # (scene, caller) -> row -> draws covering it
info = collections.defaultdict(lambda: {"draws": 0, "mir": 0, "art": 0, "lo": 999, "hi": -999, "cols": [99, -99]})
fills = collections.defaultdict(collections.Counter)
for run in runs:
    for line in open(run.rstrip("/\\") + "/assetlog.log"):
        p = line.split()
        if p[0] == "B" and len(p) >= 12:
            sc, kind, src, bank, h, w, caller = int(p[2]), p[4], int(p[5], 16), int(p[6]), int(p[7]), int(p[8]), p[9]
            col, top = int(p[10]), int(p[11]) - ROW0
            e = info[(sc, caller)]
            e["draws"] += 1
            e["mir"] += kind in ("M", "MR")
            e["art"] += bank == 14 and 0x8000 <= src < 0xA000
            e["lo"] = min(e["lo"], top)
            e["hi"] = max(e["hi"], top + h - 1)
            c0 = col - (w - 1 if kind in ("AR", "MR") else 0)
            e["cols"] = [min(e["cols"][0], c0), max(e["cols"][1], c0 + w - 1)]
            for r in range(top, top + h):
                rows[(sc, caller)][r] += 1
        elif p[0] == "F" and len(p) >= 9:
            sc, top, bot = int(p[2]), int(p[6]) - ROW0, int(p[8]) - ROW0
            for r in range(max(top, 0), bot + 1):
                fills[sc][r] += 1


def pct(cnt, q):
    tot = sum(cnt.values())
    acc = 0
    for r in sorted(cnt):
        acc += cnt[r]
        if acc >= q * tot:
            return r
    return None


for sc in sorted({k[0] for k in info}):
    print("scene %d" % sc)
    print("  %-6s %8s %11s %11s %6s %5s %9s" % ("caller", "draws", "rows", "rows 98%", "mirr%", "art%", "columns"))
    for (s, c), e in sorted(info.items(), key=lambda kv: (kv[0][0], kv[1]["lo"])):
        if s != sc or e["draws"] < 3:
            continue
        cnt = rows[(s, c)]
        print("  %-6s %8d %5d-%-5d %5s-%-5s %5.0f %5.0f %4d-%-4d" % (
            c, e["draws"], e["lo"], e["hi"], pct(cnt, 0.01), pct(cnt, 0.99),
            100.0 * e["mir"] / e["draws"], 100.0 * e["art"] / e["draws"], e["cols"][0], e["cols"][1]))
    if fills[sc]:
        print("  fills: rows %d-%d (98%%: %s-%s)" % (min(fills[sc]), max(fills[sc]), pct(fills[sc], 0.01), pct(fills[sc], 0.99)))
