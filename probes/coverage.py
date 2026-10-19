"""What no run reads, in the common code and the fixed bank (FINDINGS
"Coverage: common and bank 15"), from probes/p7800-coverage.lua's
coverage.bin files (this build's): their union, each byte mapped back to
the original (common: XEGS $06E8-$0FFF at +$9000 in every scene page;
bank 15 and the engine's parts: through scene 1's resolver), and the
original's census (executed instructions with their operands, data reads)
on top. Prints the runs of RUN or more bytes neither touched, by region,
and writes them to work/analysis/coverage-dead.txt.

    python probes/coverage.py [RUN=16] work/analysis/cv-*
"""
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import link7800 as K     # noqa: E402
import layout7800 as L   # noqa: E402
import dis as D          # noqa: E402
import m6502             # noqa: E402  (the toolkit's, on the path via dis)

args = sys.argv[1:]
RUN = 16
if args and args[0].startswith("RUN="):
    RUN = int(args.pop(0)[4:])
com, fix = bytearray(2328), bytearray(16384)
for d in args:
    p = os.path.join(d, "coverage.bin")
    if not os.path.exists(p):
        print("(no coverage.bin in %s)" % d)
        continue
    b = open(p, "rb").read()
    for i in range(2328):
        com[i] |= b[i]
    for i in range(16384):
        fix[i] |= b[2328 + i]

# the original's census: executed instructions (all their bytes) and reads
ex, rd = set(), set()
for f in glob.glob(os.path.join(K.ROOT, "census", "*.ex")):
    for ln in open(f):
        t = ln.split()
        if t:
            ex.add(int(t[0]))
rdf = glob.glob(os.path.join(K.ROOT, "census", "*.rd"))
for f in rdf:
    for ln in open(f):
        t = ln.split()
        if t:
            rd.add(int(t[0]))
m = D.memory(1)
census = set(rd)
for a in ex:
    mn, mode, _ = m6502.OPCODES[m.get(a, 0)]
    census.update(range(a, a + 1 + m6502.MODES[mode]))

link = K.link(scenes=(1,), verbose=False)
res = link["scenes"][1]["resolver"]
regions = [("common", 0x06E8, 0x1000), ("engine1", 0x1000, 0x1203), ("engine2d", 0x2300, 0x2400),
           ("engine2a", 0x2400, 0x2800), ("engine2f", 0x2C00, 0x2E00), ("engine2c", 0x2E00, 0x3000),
           ("bank15", 0xA000, 0xC000)]
reps = L.replacements(1)
replaced = {a for a0, (a1, lines) in reps.items() for a in range(a0, a1)}
out = []
for name, lo, hi in regions:
    dead = []
    for a in range(lo, hi):
        if a in replaced or a in census:
            continue
        if name == "common":
            seen = com[a - 0x06E8]
        else:
            try:
                n = res.new_addr(a)
            except Exception:
                continue
            if not 0xC000 <= n <= 0xFFFF:
                continue
            seen = fix[n - 0xC000]
        if not seen:
            dead.append(a)
    runs, r = [], None
    for a in dead + [None]:
        if r and a == r[1]:
            r[1] += 1
        else:
            if r and r[1] - r[0] >= RUN:
                runs.append(tuple(r))
            r = [a, a + 1] if a is not None else None
    tot = sum(b - a for a, b in runs)
    print("%-9s %5d bytes untouched in %d runs of %d or more" % (name, tot, len(runs), RUN))
    for a, b in runs:
        out.append("%s %04X %04X %d" % (name, a, b - 1, b - a))
with open(os.path.join(HERE, "..", "work", "analysis", "coverage-dead.txt"), "w") as f:
    f.write("\n".join(out) + "\n")
print("fixed bank read in the runs: %d of 16,384; common: %d of 2,328" % (sum(fix), sum(com)))
