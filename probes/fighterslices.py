"""The fighters' parts cut on the band's 8-line grid at the build (FINDINGS
"The fighters as objects: step 2"): each pose's parts sit at fixed rows (the
fighters have no vertical position: bank 15 places every part by its pose's
table row + $72), so each pose's merged lower body and its torso can be cut
into the grid's zones ahead of time, each slice trimmed to its opaque bytes
and given its own palette: palette 1 (skin, grey, white: all of the game's
colours) when the slice has no black, else the black palette (skin, black,
white: grey made white). Sizes in ROM (each slice's rows only, the zone's
other lines being zeros) against storing each image once.

    python probes/fighterslices.py"""
import collections
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import dis as D     # noqa: E402

m = D.memory(1)
FB_TOP, FB_BAND, ZH = 65, 27, 8
TOP = 0x72 - 35                 # a table row + $72 is the XEGS line; less 35 the buffer row


def grid(r):
    """the 8-line grid zone (first, last row) holding buffer row r"""
    c0 = FB_TOP + (r - FB_TOP) // FB_BAND * FB_BAND
    z0 = c0 + (r - c0) // ZH * ZH
    return z0, min(z0 + ZH, c0 + FB_BAND) - 1


def img(a):
    r, w = m[a], m[a + 1]
    return r, w, [[(m[a + 2 + y * w + b] >> (6 - 2 * k)) & 3 for b in range(w) for k in range(4)] for y in range(r)]


def signed(v):
    return v - 256 if v >= 128 else v


def tab(lo, hi, n):
    return [m[lo + i] | m[hi + i] << 8 for i in range(n)]


def lower_part(x):
    """pose x's merged lower body: (x, row) -> value; 'K' for the mask's black"""
    s, mk = tab(0xA000, 0xA02A, 42)[x], tab(0xA0A8, 0xA0D2, 42)[x]
    row, mrow, mcol = m[0xA07E + x], m[0xA126 + x], signed(m[0xA0FC + x])
    out = {}
    if mk >> 8:
        mr, mw, mp = img(mk)
        for y in range(mr):
            for xx in range(mw * 4):
                if mp[y][xx] == 0:
                    out[(xx + mcol * 4, y + mrow + TOP)] = "K"
    sr, sw, sp = img(s)
    for y in range(sr):
        for xx in range(sw * 4):
            if sp[y][xx]:
                out[(xx, y + row + TOP)] = sp[y][xx]
    return out


def upper_part(x, head=True):
    """pose x's torso (all colours), with the player's head (its colours) on"""
    s = tab(0xA226, 0xA24C, 38)[x]
    out = {}
    sr, sw, sp = img(s)
    tcol, trow = m[0xA272 + x], m[0xA298 + x]
    for y in range(sr):
        for xx in range(sw * 4):
            if sp[y][xx]:
                out[(xx, y + trow + TOP)] = sp[y][xx]
    black = {}
    if head:
        hy = m[0xA1A4 + x]
        hy = hy - 7 if hy >= 8 else 0
        hs = m[0xA1CD + hy] | m[0xA1CA + hy] << 8
        hm = m[0xA1D9 + hy] | m[0xA1D6 + hy] << 8
        hcol, hrow = signed(m[0xA1DA + x]) - signed(tcol), m[0xA200 + x]
        hr, hw, hp = img(hs) if hs >> 8 else (0, 0, [])
        mr, mw, mp = img(hm) if hm >> 8 else (0, 0, [])
        for y in range(mr):
            for xx in range(mw * 4):
                if mp[y][xx] == 0:
                    black[(xx + hcol * 4, y + hrow + TOP)] = "K"
        for y in range(hr):
            for xx in range(hw * 4):
                if hp[y][xx]:
                    out[(xx + hcol * 4, y + hrow + TOP)] = hp[y][xx]
                    black.pop((xx + hcol * 4, y + hrow + TOP), None)
    return out, black


def slices(px):
    """per grid zone: (zone, b0, b1, rows used, has black, grey pixels)"""
    by = collections.defaultdict(dict)
    for (x, y), v in px.items():
        by[grid(y)][(x, y)] = v
    out = []
    for z, p in sorted(by.items()):
        xs = [x for x, y in p]
        ys = [y for x, y in p]
        out.append((z, min(xs) // 4, max(xs) // 4, max(ys) - min(ys) + 1,
                    any(v == "K" for v in p.values()), sum(1 for v in p.values() if v == 2)))
    return out


def size(sl):
    return sum((b1 - b0 + 1) * n for z, b0, b1, n, k, g in sl)


def main():
    lo_s = tab(0xA000, 0xA02A, 42)
    seen, lower_bytes, once = {}, 0, {}
    nsl = nk = grey_kept = grey_all = 0
    for x in range(42):
        key = (lo_s[x], tab(0xA0A8, 0xA0D2, 42)[x], m[0xA07E + x], m[0xA126 + x], m[0xA0FC + x])
        if key in seen:
            continue
        px = lower_part(x)
        sl = slices(px)
        seen[key] = sl
        lower_bytes += size(sl)
        for z, b0, b1, n, k, g in sl:
            nsl += 1
            nk += k
            grey_all += g
            grey_kept += 0 if k else g
        ik = (lo_s[x], key[1])
        if ik not in once:
            xs = [p[0] for p in px]
            ys = [p[1] for p in px]
            once[ik] = ((max(xs) // 4 - min(xs) // 4 + 1) * (max(ys) - min(ys) + 1))
    print("lower bodies: %d poses' parts, %d slices (%d with black), %d bytes pre-cut; each image once "
          "(whole boxes) %d bytes" % (len(seen), nsl, nk, lower_bytes, sum(once.values())))
    print("  grey pixels: %d, kept (slices without black) %d" % (grey_all, grey_kept))
    up_s = tab(0xA226, 0xA24C, 38)
    useen, ub, kb, nsl = {}, 0, 0, 0
    for x in range(38):
        key = (up_s[x], m[0xA298 + x], m[0xA1A4 + x], m[0xA1DA + x] - m[0xA272 + x], m[0xA200 + x])
        if key in useen:
            continue
        col, blk = upper_part(x)
        sl, bl = slices(col), slices(blk)
        useen[key] = 1
        ub += size(sl)
        kb += size(bl)
        nsl += len(sl)
    print("torsos with the player's head: %d poses' parts, %d slices, %d bytes; the head's black layer %d bytes"
          % (len(useen), nsl, ub, kb))


if __name__ == "__main__":
    main()
