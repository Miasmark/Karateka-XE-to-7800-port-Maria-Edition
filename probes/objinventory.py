"""A scene's object shapes without the blitter (FINDINGS "Levels 2-4 without
the blitter"), as probes/l1inventory.py makes level 1's: every blit of the
scene's pictures in p7800-l1cap.lua logs (the state record tells each
picture's scene: p7800-staterec.lua's state.bin), one line a shape:
    B src bank mir row mode   (seen, seen at a pixel shift)
and its fills that paint something (not the fighter-box erases, S_NOFILL):
    F kind top bottom v02 v12 c0 c1   (seen)   (columns as drawn, 0-40)

    python probes/objinventory.py SCENE OUT LOG:STATE.BIN [LOG:STATE.BIN ...]"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "port"))
from l1worldlist import state_mode      # noqa: E402
import layout7800 as L                  # noqa: E402


def main():
    scene, out = int(sys.argv[1]), sys.argv[2]
    bank, shapes, fills, shifted = {}, Counter(), Counter(), Counter()
    srcs = []
    for arg in sys.argv[3:]:
        path, st = arg.rsplit(":", 1) if arg.count(":") > 1 else arg.split(":")
        srcs.append(path)
        modes = state_mode(st)
        pend = []
        for line in open(path):
            p = line.split()
            if p[0] == "I":
                continue
            if p[0] != "P":
                pend.append(p)
                continue
            n = int(p[1])
            if modes.get(n, (None, None, None))[1] == scene:
                for q in pend:
                    if q[0] == "B":
                        # (the draw's own bank: the scene page's or the art
                        # bank's; another page's is the scene before's last
                        # picture, drawn as $D0 changed)
                        src, bk = int(q[7], 16), int(q[8])
                        if bk not in (L.ART_BANK, L.SCENE_BANK[scene]):
                            continue
                        bank[src] = bk
                        k = ("B", src, int(q[2] in ("M", "MR")), int(q[5]), int(q[3], 16))
                        shapes[k] += 1
                        if int(q[6]):
                            shifted[k] += 1
                    elif q[0] == "F" and q[10] == "0":
                        fills[(q[2], int(q[6]), int(q[5]), int(q[8], 16), int(q[9], 16), int(q[3]), int(q[4]))] += 1
            pend = []
    with open(out, "w", newline="\n") as o:
        o.write("# scene %d's shapes below row 65 (probes/objinventory.py from %s)\n"
                % (scene, ", ".join(os.path.relpath(p, os.path.join(HERE, "..")).replace("\\", "/") for p in srcs)))
        o.write("# B src bank mir row mode | F kind top bottom v02 v12 c0 c1   (seen[, seen shifted])\n")
        for k in sorted(shapes):
            o.write("%s %04X %d %d %d %d   %d %d\n" % (k[0], k[1], bank[k[1]], k[2], k[3], k[4], shapes[k], shifted[k]))
        for k in sorted(fills):
            o.write("F %s %d %d %02X %02X %d %d   %d\n" % (k + (fills[k],)))
    print("scene %d: %d shapes, %d fills to %s" % (scene, len(shapes), len(fills), out))


if __name__ == "__main__":
    main()
