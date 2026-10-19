"""Each scene's load against the build's knowledge of it (FINDINGS "The ROM
by scene: step 1"): probes/tmp-loadcap.lua's loadcap_<scene>.bin (cart RAM
after the load) and the build's <cart>.loadimg (bytes and flags: 1 tiles,
map rows and windows; 2 a pose's cell, the build's cut; 3 the black block), and what
MARIA fetched from cart RAM in the scene (tmp-romuse.lua's "C" region).
Per scene: the build's bytes that match and those that don't (the first
few), the pose cells' size, and MARIA's fetches the build has no byte for.
    python probes/loadcmp.py LOADIMG CAPTURE_DIR... [--romuse RUN_DIR...]"""
import os
import sys
from collections import defaultdict

SCENES = (0, 1, 2, 3, 4, 6)
args = sys.argv[1:]
ru = []
if "--romuse" in args:
    i = args.index("--romuse")
    ru, args = args[i + 1:], args[:i]
img, caps = args[0], args[1:]
raw = open(img, "rb").read()
mread = defaultdict(set)
for d in ru:
    for ln in open(d + "/romuse.log"):
        bk, ph, sc, kind, page, bits = ln.split()
        if bk != "C" or kind != "m":
            continue
        page = int(page, 16)
        for i, ch in enumerate(bits):
            v = int(ch, 16)
            for j in range(4):
                if v & (8 >> j):
                    mread[int(sc)].add(page * 256 + 4 * i + j)
for k, sc in enumerate(SCENES):
    data, flag = raw[k * 0x8000:k * 0x8000 + 0x4000], raw[k * 0x8000 + 0x4000:(k + 1) * 0x8000]
    cap = next((os.path.join(d, "loadcap_%d.bin" % sc) for d in caps
                if os.path.exists(os.path.join(d, "loadcap_%d.bin" % sc))), None)
    if not cap:
        print("scene %d: no capture" % sc)
        continue
    c = open(cap, "rb").read()
    same, diff, n = 0, [], defaultdict(int)
    for i in range(0x4000):
        if flag[i]:
            n[flag[i]] += 1
        if flag[i] in (1, 2, 3):
            if c[i] == data[i]:
                same += 1
            else:
                diff.append(0x4000 + i)
    miss = sorted(a for a in mread[sc] if not flag[a - 0x4000])
    pose_read = sum(1 for a in mread[sc] if flag[a - 0x4000] == 2)
    print("scene %d: build's bytes %d (tiles %d, poses %d, black %d); match %d, differ %d%s; MARIA reads %d, "
          "%d of them pose cells, %d the build has no byte for%s"
          % (sc, sum(n.values()), n[1], n[2], n[3], same, len(diff),
             (" (first " + " ".join("$%04X" % a for a in diff[:8]) + ")") if diff else "",
             len(mread[sc]), pose_read, len(miss),
             (" (pages " + " ".join(sorted({"%02X" % (a >> 8) for a in miss})) + ")") if miss else ""))
