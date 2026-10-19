"""Check a status-bar sweep (probes/p7800-stsweep.lua's stsweep.log).

    python probes/stsweep.py work/analysis/stsweep/stsweep.log

Every frame, the buffer on screen (the one $07 does not name: the other is
being drawn, its list cleared and built again): the rows MARIA shows are the
game's arrows for the counts set (layout7800.arrow_rows, as the game draws them: the player's
from x = 0, the foe's from 155 leftwards). In each hold's last 10 frames: the
counts set are the health, but none below 3 in buffer B (the blink, as the
game's $0B55/$0B9E). The warning tune: once each time the player's health
goes below 3 from 3 or more.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "port"))
import layout7800 as L   # noqa: E402


def expected(p, f):
    # the game draws the foe's arrows after the player's, each opaque over
    # its 4-pixel place, and both bars keep to the same 5-pixel places: where
    # they meet, the player's are hidden (32 places across)
    p = min(p, max(0, 32 - f))
    pr = L.arrow_rows(0x0B12, True, [5 * i for i in range(p)])
    fr = L.arrow_rows(0x0B1C, False, [155 - 5 * i for i in range(f)])
    # where they overlap, the foe's pixels over the player's (the game's
    # blits and MARIA's objects alike)
    out = []
    for r in range(7):
        for a, b in zip(pr[r], fr[r]):
            m = 0
            for k in range(4):
                if (b >> 2 * k) & 3:
                    m |= 3 << 2 * k
            out.append("%02X" % ((a & ~m) | b))
    return "".join(out)


PAIRS = [(k, 28 - k) for k in range(1, 28)] + [(1, 1), (2, 2), (3, 3), (1, 2), (2, 1), (4, 4),
                                              (24, 1), (1, 24), (25, 3), (3, 25)]   # the probe's


def main():
    bad, frames, seen, tunes, holds = 0, 0, set(), [], {}
    for line in open(sys.argv[1]):
        if line.startswith("tune"):
            tunes.append(int(line.split()[1][1:]))
            continue
        if not line.startswith("w"):
            print(line.strip())
            continue
        head, *bufs = line.strip().split(" | ")
        h = head.split()
        i, w, fr = int(h[0][1:]), int(h[1]), int(h[2][1:])
        b6, b7, z07 = int(h[3][3:]), int(h[4][3:]), int(h[5][3:], 16)
        holds.setdefault(i, fr)
        frames += 1
        for k, b in enumerate(bufs):
            if k != (1 if z07 == 0x40 else 0):
                continue
            p, f, n, rows = b.split()
            p, f = int(p), int(f)
            seen.add((p, f))
            if rows != expected(p, f):
                bad += 1
                if bad <= 10:
                    print("hold %d frame %d buffer %s: counts %d/%d, the rows shown differ" % (i, fr, "AB"[k], p, f))
            if w >= HOLD_CHECK:
                wp = b6 if (b6 >= 3 or k == 0) else 0
                wf = b7 if (b7 >= 3 or k == 0) else 0
                if (p, f) != (wp, wf):
                    bad += 1
                    if bad <= 10:
                        print("hold %d frame %d buffer %s: counts %d/%d, health %d/%d" % (i, fr, "AB"[k], p, f, b6, b7))
    # the tune: holds whose player health is below 3 after one at 3 or more
    want = [holds[i] for i in sorted(holds) if PAIRS[i - 1][0] < 3 and (i == 1 or PAIRS[i - 2][0] >= 3)]
    print("%d frames, %d count pairs shown, %d mismatches" % (frames, len(seen), bad))
    print("warning tune at frames %s; expected one at each of %s" % (tunes, want))
    ok = bad == 0 and len(tunes) == len(want) and all(-1 <= t - s <= 10 for t, s in zip(tunes, want))
    print("OK" if ok else "FAILED")


HOLD_CHECK = 30
if __name__ == "__main__":
    main()
