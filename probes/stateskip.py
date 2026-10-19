"""The game-state bytes a replay must leave alone (FINDINGS "Replaying a
recording on another build"): those that are this build's own, not the
game's, i.e. pointers into code or tables that moved between the builds
(the engine's vertical-blank vector, zero-page vectors). Found by comparing
the recording's states (p7800-staterec.lua on its own cartridge) with this
build's own states for the same flips (p7800-staterec.lua on this build, the
recording played without forcing, a few hundred frames): a byte that differs
at most of the first flips is a pointer; its pair's other byte goes too.

    python probes/stateskip.py RECORDED.bin THISBUILD.bin [FLIPS] > skip.txt
Output: a comma list of hex addresses, for p7800-stateplay.lua's SKIP.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
addrs = [int(l, 16) for l in open(os.path.join(HERE, "..", "work", "gamestate.txt"))]
a, b = open(sys.argv[1], "rb").read(), open(sys.argv[2], "rb").read()
n = len(addrs)
flips = min(len(a) // n, len(b) // n, int(sys.argv[3]) if len(sys.argv) > 3 else 8)
skip = set()
for i, ad in enumerate(addrs):
    diff = sum(1 for r in range(flips) if a[r * n + i] != b[r * n + i])
    if diff * 4 >= flips * 3:
        skip.update((ad - 1, ad, ad + 1))
skip &= set(addrs)
print(",".join("%04X" % x for x in sorted(skip)))
