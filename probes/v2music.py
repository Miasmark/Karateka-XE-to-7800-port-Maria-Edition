"""The tunes' bytes in each scene page (FINDINGS "The V2 release audit"):
the engine's tune table ($25C0, 28 tunes) -> tune lists (words to $FF,
4-byte $FE/$FD commands) -> pattern references (a word) -> note streams
(a header pointer, 3-byte notes, 2-byte $FE changes, to $FF) -> headers
(4 variants of 7 bytes, $259D/$2652: 28 bytes), within the music region
(reloclist.MUSIC); and which of them V2's release gives back (as
build7800 does: no instruction, label or relocation there).
    V2=1 python probes/v2music.py
"""
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import dis as D                 # noqa: E402
import layout7800 as L          # noqa: E402
import link7800 as K            # noqa: E402
import reloclist as RL          # noqa: E402
import xesource as X            # noqa: E402

LO, HI = RL.MUSIC


def tune_bytes(mem):
    w = lambda a: mem[a] | mem[a + 1] << 8
    out = set()
    for i in range(28):
        t = w(0x25C0 + 2 * i)
        if not LO <= t < HI:
            continue
        k = 0
        while mem.get(t + k + 1) is not None and mem[t + k + 1] != 0xFF:
            out |= {t + k, t + k + 1}
            if mem[t + k + 1] in (0xFE, 0xFD):
                out |= set(range(t + k, t + k + 4))
                k += 4
                continue
            p = w(t + k)
            if LO <= p < HI:
                q = w(p)
                if LO <= q < HI and RL.music_stream(mem, q):
                    out |= {p, p + 1}
                    h = w(q)
                    out |= set(range(h, h + 28))
                    j = q + 2
                    out |= {q, q + 1}
                    while mem[j] != 0xFF:
                        n = 2 if mem[j] == 0xFE else 3
                        out |= set(range(j, j + n))
                        j += n
                    out.add(j)
            k += 2
        out |= {t + k, t + k + 1}
    return out


car = open(K.CAR, "rb").read()
ex = glob.glob(os.path.join(K.ROOT, "census", "*.ex"))
reloc = os.path.join(K.ROOT, "reloc.txt")
models = {s: X.analyse(car, s, ex, reloc) for s in L.SCENES}
keep = {}
for s in L.PAGE_SCENES:
    here = [t for t in L.SCENES if L.SCENE_BANK[t] == L.SCENE_BANK[s]]
    ms = [models[t] for t in here]
    labs = {v for m in ms for v in m.symbols.values()}
    released = set()
    for lo, hi in L.V2_PAGE_RELEASE.get(s, []) + L.V2_CODE_RELEASE.get(s, []):
        for x in range(lo, hi):
            if not (x in labs or any(x in m.insn or x in m.reloc for m in ms)):
                released.add(x)
    tb = set()
    for t in here:
        tb |= tune_bytes(D.memory(t))
    hit = sorted(tb & released)
    runs = []
    for x in hit:
        if runs and x == runs[-1][1]:
            runs[-1][1] = x + 1
        else:
            runs.append([x, x + 1])
    keep[s] = [(a, b) for a, b in runs]
    print("scene %d's page: tunes %d bytes, %d of them released: %s" % (
        s, len(tb), len(hit), ", ".join("$%04X-$%04X" % (a, b - 1) for a, b in runs)))
print("KEEP =", {s: ["(0x%04X, 0x%04X)" % r for r in v] for s, v in keep.items()})
