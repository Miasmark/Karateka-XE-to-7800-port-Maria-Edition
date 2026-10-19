"""How much of the XEGS cartridge's banks are the same bytes: for pairs of
banks, the bytes identical at the same offset (in runs of at least MINRUN),
and the bytes of one found anywhere in the other (runs of at least MINRUN,
greedy). Scene banks: code 13/7/1/5/3/9, data 11/8/2/6/4/10 (scenes 0, 1,
2, 3, 4, 6).
    python probes/bankoverlap.py [MINRUN]"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CAR = os.environ.get("KARATEKA_CAR", os.path.join(HERE, "..", "..", "karateka", "Karateka.car"))
car = open(CAR, "rb").read()[16:]
bank = lambda n: car[n * 0x2000:(n + 1) * 0x2000]
MINRUN = int(sys.argv[1]) if len(sys.argv) > 1 else 16


def same_offset(a, b):
    n, run = 0, 0
    for i in range(len(a)):
        if a[i] == b[i]:
            run += 1
        else:
            if run >= MINRUN:
                n += run
            run = 0
    return n + (run if run >= MINRUN else 0)


def anywhere(a, b):
    """bytes of a covered by runs (>= MINRUN) found somewhere in b"""
    n, i = 0, 0
    while i < len(a):
        if a[i:i + MINRUN] in b:
            k = MINRUN
            while i + k < len(a) and a[i:i + k + 1] in b:
                k += 1
            n += k
            i += k
        else:
            i += 1
    return n


DATA = {0: 11, 1: 8, 2: 2, 3: 6, 4: 4, 6: 10}
CODE = {0: 13, 1: 7, 2: 1, 3: 5, 4: 3, 6: 9}
for kind, m in (("data", DATA), ("code", CODE)):
    print("%s banks (scene: bank), bytes the same at the same offset / found anywhere in the other:" % kind)
    sc = sorted(m)
    for x in sc:
        for y in sc:
            if x < y:
                a, b = bank(m[x]), bank(m[y])
                print("  scenes %d-%d (banks %2d, %2d): %5d / %5d" % (x, y, m[x], m[y], same_offset(a, b), anywhere(a, b)))
