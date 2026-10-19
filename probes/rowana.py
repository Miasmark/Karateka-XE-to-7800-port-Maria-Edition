"""Rows LO-HI (default 45-78) of the original's finished pictures, as MARIA
might show them (FINDINGS "Rows 45-78 as objects: the costed plan"), from
playkey.lua MACHINE=xe framebuffer dumps (fbk<N>.bin: buffers A and B,
153 rows of 40 bytes each).

Each row is split into a background and what's left:
- the background: the repeating pattern (period p bytes, 1-20, at fixed
  columns) that matches most of the row's bytes; uniform rows (p = 1) cost
  nothing as objects if shown as the background colour;
- the rest: the runs of bytes the pattern doesn't match, one object each.

Per scene, over every dump and both buffers (avg / 95% / max where it
varies):
- each row: its period, how often it is uniform and with what byte, how
  many different contents it takes (does it move);
- per line: rest objects and bytes; MARIA's time with the background as
  objects of TILE bytes (40 / TILE of them, reading one stored tile) plus
  the rest (about 2.25 cycles an object and 0.75 a byte; a line has 113.5);
- data: the tiles (TILE bytes a distinct background pattern) and the
  distinct rest runs (as drawn, i.e. counting each pixel shift apart: an
  upper bound for pieces MARIA would place by the pixel).

    python probes/rowana.py [LO HI] [TILE=8] work/analysis/fbx-s1 [...]
Only dumps taken in the run's own scene count (playkey.log's $D0 at each:
fbx-s<N>, N 1-4, or 6, which plays as $D0 = 1)."""
import collections
import glob
import os
import re
import sys

ROWLEN, ROWS = 40, 153


def best_pattern(row):
    best = None
    for p in range(1, 21):
        pat = []
        miss = 0
        for k in range(p):
            col = row[k::p]
            v, n = collections.Counter(col).most_common(1)[0]
            pat.append(v)
            miss += len(col) - n
        if best is None or miss < best[0]:
            best = (miss, p, bytes(pat))
    return best


def runs(row, p, pat):
    out, i = [], 0
    while i < ROWLEN:
        if row[i] != pat[i % p]:
            j = i
            while j < ROWLEN and row[j] != pat[j % p]:
                j += 1
            out.append(row[i:j])
            i = j
        else:
            i += 1
    return out


def stats(v):
    v = sorted(v)
    if not v:
        return "-"
    return "%.0f / %.0f / %.0f" % (sum(v) / len(v), v[int(len(v) * 0.95)], v[-1])


def main():
    args = sys.argv[1:]
    LO, HI = (int(args.pop(0)), int(args.pop(0))) if args and args[0].isdigit() else (45, 78)
    TILE = 8
    if args and args[0].startswith("TILE="):
        TILE = int(args.pop(0)[5:])
    for d in args:
        want = int(re.search(r"-s(\d+)", os.path.basename(d.rstrip("/"))).group(1))   # (fbx-s<N>, fb78-s<N>)
        d0 = {}
        for line in open(os.path.join(d, "playkey.log")):
            t = line.split()
            if t and t[0] == "flip" and t[2].startswith("D0="):
                d0[int(t[1])] = int(t[2][3:], 16)
        files = sorted(fn for fn in glob.glob(os.path.join(d, "fbk*.bin"))
                       if d0.get(int(os.path.basename(fn)[3:-4])) == (1 if want == 6 else want))
        per_row = collections.defaultdict(lambda: {"p": collections.Counter(), "uni": collections.Counter(),
                                                   "contents": set(), "pats": set()})
        line_objs, line_bytes, line_t, pic_rest = [], [], [], []
        tiles, rest_runs = set(), set()
        for fn in files:
            data = open(fn, "rb").read()
            for b in range(2):
                buf = data[b * ROWS * ROWLEN:(b + 1) * ROWS * ROWLEN]
                if len(buf) < ROWS * ROWLEN:
                    continue
                total_rest = 0
                for r in range(LO, HI + 1):
                    row = buf[r * ROWLEN:(r + 1) * ROWLEN]
                    miss, p, pat = best_pattern(row)
                    e = per_row[r]
                    e["p"][p] += 1
                    e["contents"].add(row)
                    if p == 1:
                        e["uni"][pat[0]] += 1
                    else:
                        e["pats"].add(pat)
                        tiles.add((pat * (TILE // p + 1))[:TILE] if TILE % p == 0 else pat)
                    rs = runs(row, p, pat)
                    for x in rs:
                        rest_runs.add((r, x))
                    nb = sum(len(x) for x in rs)
                    t = 2.25 * len(rs) + 0.75 * nb
                    if p > 1:
                        t += 2.25 * (ROWLEN // TILE) + 0.75 * ROWLEN
                    line_objs.append(len(rs))
                    line_bytes.append(nb)
                    line_t.append(t)
                    total_rest += len(rs)
                pic_rest.append(total_rest)
        print("%s: rows %d-%d, %d dumps (both buffers), tile %d bytes" % (d, LO, HI, len(files), TILE))
        print("  row: period (most seen), uniform byte (share), contents seen")
        for r in range(LO, HI + 1):
            e = per_row[r]
            n = sum(e["p"].values())
            p, pn = e["p"].most_common(1)[0]
            u = ", ".join("$%02X %d%%" % (v, 100 * c // n) for v, c in e["uni"].most_common(2))
            print("   %3d  p%-2d (%3d%%)  %-22s %d" % (r, p, 100 * pn // n, u, len(e["contents"])))
        print("  per line: rest objects %s; rest bytes %s; MARIA cycles %s" % (
            stats(line_objs), stats(line_bytes), stats(line_t)))
        print("  rest objects a picture (rows %d-%d): %s" % (LO, HI, stats(pic_rest)))
        print("  data: %d background tiles (%d bytes), %d distinct rest runs (%d bytes)" % (
            len(tiles), sum(len(t) for t in tiles), len(rest_runs), sum(len(x) for _, x in rest_runs)))


if __name__ == "__main__":
    main()
