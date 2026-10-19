"""Simulate reusing the fighters' copied parts (FINDINGS "The fighters as
objects: speed") on probes/p7800-ftsame.lua's SEQ=1 log.

    python probes/ftcache.py work/analysis/fsame1/ftseq.log [...]

A part is a fighter's lower body (key: slot, $20) or upper body (slot,
$21, $3E, $36); its cost the columns it took. Schemes:
  own:   reused when the same buffer's same slot had it at its last emit;
  pool N: a pool of N columns over both buffers, least recently used out,
         never a part the other buffer shows (its last emit's parts).
Prints the share of columns copied that each scheme saves.
"""
import sys


def parse(path):
    for line in open(path):
        f = line.split()
        if not f:
            continue
        buf, parts = int(f[0]), []
        for t in f[1:]:
            head, cols = t.split("/")
            slot, rest = head.split(":")
            v = [int(x) for x in rest.split(",")]
            lc, uc = [int(x) for x in cols.split(",")]
            parts.append((("L", int(slot), v[0]), lc))
            parts.append((("U", int(slot), v[1], v[2], v[3]), uc))
        yield buf, parts


def own(seq):
    last, tot, saved = {}, 0, 0
    for buf, parts in seq:
        now = {}
        for k, c in parts:
            tot += c
            slotkey = (buf, k[0], k[1])
            if last.get(slotkey) == k:
                saved += c
            now[slotkey] = k
        last.update(now)
    return saved / max(tot, 1)


def pool(seq, size):
    lru, shown, tot, saved = {}, {0: set(), 1: set()}, 0, 0
    t = 0
    for buf, parts in seq:
        t += 1
        keep = shown[1 - buf]
        mine = set()
        for k, c in parts:
            tot += c
            if k in lru:
                saved += c
            else:
                while sum(lru[x][1] for x in lru) + c > size:
                    old = [x for x in lru if x not in keep and x not in mine]
                    if not old:
                        break
                    del lru[min(old, key=lambda x: lru[x][0])]
            lru[k] = (t, c)
            mine.add(k)
        shown[buf] = mine
    return saved / max(tot, 1)


for path in sys.argv[1:]:
    seq = list(parse(path))
    print("%s: own %.0f%%, pool 224 %.0f%%, pool 160 %.0f%%, pool 112 %.0f%%" % (
        path, 100 * own(seq), 100 * pool(seq, 224), 100 * pool(seq, 160), 100 * pool(seq, 112)))
