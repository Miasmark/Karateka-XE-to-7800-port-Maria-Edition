"""Replay probes/p7800-toplog.lua logs per buffer: a draw above the cut adds a
piece, a clear empties the buffer, a copy copies it; for each fill, whether
the pieces under it are covered whole or in part. Run from work/analysis
(the logs as arguments; default top1/ and top2/)."""
import sys, collections
CUT = 45
def analyse(path):
    objs = {'A': [], 'B': []}
    fills = collections.Counter(); partial = []; whole = 0; draws = 0; kinds = collections.Counter()
    for line in open(path):
        p = line.split()
        if p[0] == 'C':
            objs[p[2]] = []
        elif p[0] == 'K':
            objs[p[2]] = list(objs['B' if p[2] == 'A' else 'A'])
        elif p[0] == 'B':
            f, b, kind, src, rows, width, x, top = int(p[1]), p[2], p[3], p[4], int(p[5]), int(p[6]), int(p[7]), int(p[8])
            draws += 1; kinds[(src, kind, rows, width, top)] += 1
            objs[b].append((x, x + 4 * width - 1, top, min(top + rows - 1, CUT - 1), src, f))
        elif p[0] == 'F':
            f, b, kind, c0, c1, top, bot, val = int(p[1]), p[2], p[3], int(p[4]), int(p[5]), int(p[6]), int(p[7]), p[8]
            fills[(c0, c1, top, bot, val)] += 1
            fx0, fx1, ft, fb = 4 * c0, 4 * c1 - 1, max(top, 0), bot
            keep = []
            for o in objs[b]:
                x0, x1, t, bt = o[0], o[1], o[2], o[3]
                vx0, vx1 = max(x0, 0), min(x1, 159)          # the part on screen
                if vx0 > vx1 or t > bt:
                    keep.append(o); continue
                inter = not (vx1 < fx0 or vx0 > fx1 or bt < ft or t > fb)
                if not inter:
                    keep.append(o); continue
                if fx0 <= vx0 and vx1 <= fx1 and ft <= t and bt <= fb:
                    whole += 1
                else:
                    partial.append((f, b, o, (c0, c1, top, bot, val)))
                    keep.append(o)
            objs[b] = keep
    print(path, ': draws above the cut', draws, '; erased whole', whole, '; partly', len(partial))
    for k, n in fills.most_common(12): print('   fill cols %d-%d rows %d-%d value %s: %d' % (k + (n,)))
    for x in partial[:12]: print('   partial: frame %d buf %s obj x %d-%d rows %d-%d src %s (drawn f%d) by fill %s' % ((x[0], x[1]) + x[2] + (x[3],)))
    return kinds
for path in (sys.argv[1:] or ['top1/toplog.log', 'top2/toplog.log']):
    k = analyse(path)
    print('   images (src kind rows width top):', sorted({(a, b, c, d, e) for a, b, c, d, e in k}))
