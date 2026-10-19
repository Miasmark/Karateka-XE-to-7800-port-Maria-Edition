"""The list allocators replayed (FINDINGS "Console RAM: the lists replayed"):
probes/tmp-listseq.lua's rebuilds, each row's lists in order, placed
first-fit in a layout's pieces as BandWL1 and TpPlace do (a band list needs
room for its estimate, then takes its real size; a top list its exact size).
Prints, per row, the rebuilds that don't fit (a list with no piece: objects
dropped in the game), the largest sum of real sizes, and the room a single
piece would need.
    python probes/listsim.py RUN_PREFIX (--sym SYMFILE | --plan MODULE.py) [--exact] [--grow PCT]
--exact: band lists placed by their real size (as if counted first).
--grow: every list PCT% longer (a margin test)."""
import argparse
import importlib.util
import os

SCENES = (0, 1, 2, 3, 4, 6)
LET = {0x00: "A", 0x08: "B", 0x10: "C", 0x18: "D", 0x20: "E", 0x28: "F"}


def pieces_sym(path):
    sym = {}
    for ln in open(path):
        p = ln.split()
        if len(p) == 2:
            try:
                sym[p[1]] = int(p[0], 16)
            except ValueError:
                pass
    out = {}
    for kind, pre in (("band", "L1S"), ("top", "TPS")):
        for row, let in LET.items():
            ps = []
            for k in range(7):
                lo, hi = sym.get("%s%s%d" % (pre, let, k)), sym.get("%s%s%dE" % (pre, let, k))
                if lo and hi and hi > lo:
                    ps.append((lo, hi))
            out[(kind, row)] = ps
    return out


def pieces_plan(path):
    spec = importlib.util.spec_from_file_location("plan", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    out = {}
    for g in (0x00, 0x10, 0x20):
        for kind, nm in (("band", "BAND"), ("top", "TOP")):
            out[(kind, g)] = list(getattr(m, "G%02X_%s_A" % (g, nm)))
            out[(kind, g + 8)] = list(getattr(m, "G%02X_%s_B" % (g, nm)))
    return out


def load(prefix):
    eps = []
    for s in SCENES:
        p = "%s%d/listseq.log" % (prefix, s)
        if not os.path.exists(p):
            continue
        for ln in open(p):
            f = ln.split()
            n, kind, row, ph = int(f[0]), f[1], int(f[2], 16), f[3]
            lists = []
            for t in f[4:]:
                if kind == "band":
                    e, r = t.split(":")
                    if r == "x":
                        continue        # (the try that didn't fit: its retry follows)
                    lists.append((int(e), int(r)))
                else:
                    lists.append((int(t), int(t)))
            eps.append((s, n, kind, row, ph, lists))
    return eps


def place(ps, lists, exact, grow):
    ptr = [lo for lo, _ in ps]
    for e, r in lists:
        if grow:
            e, r = e + (e * grow + 99) // 100, r + (r * grow + 99) // 100
        need = r if exact else e
        for k, (lo, hi) in enumerate(ps):
            if ptr[k] + need <= hi:
                ptr[k] += r
                break
        else:
            return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prefix")
    ap.add_argument("--sym")
    ap.add_argument("--plan")
    ap.add_argument("--exact", action="store_true")
    ap.add_argument("--grow", type=int, default=0)
    ap.add_argument("--show", action="store_true", help="print each failing rebuild")
    o = ap.parse_args()
    pcs = pieces_sym(o.sym) if o.sym else pieces_plan(o.plan)
    eps = load(o.prefix)
    stat = {}
    for s, n, kind, row, ph, lists in eps:
        key = (kind, row)
        st = stat.setdefault(key, {"fail": 0, "rebuilds": 0, "peak": 0, "one": 0, "scenes": set(), "where": []})
        st["rebuilds"] += n
        st["peak"] = max(st["peak"], sum(r for _, r in lists))
        acc, one = 0, 0
        for e, r in lists:
            one = max(one, acc + (r if o.exact else e))
            acc += r
        st["one"] = max(st["one"], one)
        if not place(pcs.get(key, []), lists, o.exact, o.grow):
            st["fail"] += n
            st["scenes"].add((s, ph))
            if o.show:
                print("  fails: scene %d %s %02X x%d: %s" % (s, kind, row, n, " ".join("%d:%d" % x for x in lists)))
    bad = 0
    for key in sorted(stat):
        st = stat[key]
        room = sum(hi - lo for lo, hi in pcs.get(key, []))
        sizes = sorted((hi - lo for lo, hi in pcs.get(key, [])), reverse=True)
        print("%-4s %02X: rebuilds %5d, fail %4d %s; peak %3d, one piece %3d; room %3d in %s"
              % (key[0], key[1], st["rebuilds"], st["fail"],
                 ",".join("%d%s" % x for x in sorted(st["scenes"])) or "-", st["peak"], st["one"], room, sizes))
        bad += st["fail"]
    print("fits" if bad == 0 else "FAILS: %d rebuilds" % bad)


main()
