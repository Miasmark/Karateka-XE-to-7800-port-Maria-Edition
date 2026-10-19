"""The fighters' parts for MARIA objects (FINDINGS "The fighters' parts:
masks and colours"): each part's sprite paired with its mask as bank 15
draws them, what the 160A conversion makes of it (grey to white, the black
inside the mask opaque), and the colours every part uses.

    python probes/fighterparts.py [render.png]

The parts (bank 15, scene 1's copy; the tables are the same in all):
- lower body, pose X ($20): sprite $A000/$A02A at row $A07E, column $23;
  mask $A0A8/$A0D2 (none when its high byte is 0) at row $A126, column
  $23 + $A0FC (drawn first, AND: $AA58 / $AA32 mirrored);
- head, Y from $A1A4,X ($21): mask $A1D9/$A1D6, sprite $A1CD/$A1CA (the
  player's) or the enemy's by type $3E ($AA75), at the same place;
- upper body: sprite $A226/$A24C at row $A298, OR only: no mask.
A mask's pixel 0 clears the background to black (inside the figure), 3
keeps it. Colours as indices: 1 skin, 2 grey (light blue above the band's
switch), 3 white."""
import collections
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import dis as D     # noqa: E402

m = D.memory(1)


def img(a):
    """(rows, width, pixel rows as lists of 0-3)"""
    r, w = m[a], m[a + 1]
    px = [[(m[a + 2 + y * w + b] >> (6 - 2 * k)) & 3 for b in range(w) for k in range(4)] for y in range(r)]
    return r, w, px


def tab(lo, hi, n):
    return [m[lo + i] | m[hi + i] << 8 for i in range(n)]


def signed(v):
    return v - 256 if v >= 128 else v


def compose(spr, srow, scol, msk=None, mrow=0, mcol=0):
    """the part as the original draws it over a background (None) and as
    converted: a dict (x, y) -> colour, in pixels relative to the sprite"""
    out_orig, out_conv = {}, {}
    sr, sw, sp = img(spr)
    mpx = {}
    if msk:
        mr, mw, mp = img(msk)
        for y in range(mr):
            for x in range(mw * 4):
                mpx[(x + (mcol - scol) * 4, y + mrow - srow)] = mp[y][x]
    spx = {(x, y): sp[y][x] for y in range(sr) for x in range(sw * 4)}
    for xy in set(spx) | set(mpx):
        c = spx.get(xy, 0)
        inside = mpx.get(xy, 3) == 0          # the mask clears it
        orig = c if c else (0 if inside else None)   # None: the background shows
        out_orig[xy] = orig
        conv = 3 if c == 2 else c                    # grey to white
        out_conv[xy] = conv if c else ("black" if inside else None)
    return out_orig, out_conv


def stats(name, parts):
    used, nblack, nbytes = collections.Counter(), 0, 0
    for p in parts:
        o, cv = p
        for v in o.values():
            if v is not None:
                used[v] += 1
        nblack += sum(1 for v in cv.values() if v == "black")
        xs = [x for x, y in cv]
        ys = [y for x, y in cv]
        nbytes += ((max(xs) - min(xs)) // 4 + 1) * (max(ys) - min(ys) + 1) if xs else 0
    print("%-28s %3d parts, %5d bytes as converted boxes, colours %s, %d pixels opaque black"
          % (name, len(parts), nbytes, dict(sorted(used.items())), nblack))


def main():
    lo_s, lo_m = tab(0xA000, 0xA02A, 42), tab(0xA0A8, 0xA0D2, 42)
    lo_row, lo_mrow, lo_mcol = [m[0xA07E + i] for i in range(42)], [m[0xA126 + i] for i in range(42)], \
        [signed(m[0xA0FC + i]) for i in range(42)]
    up_s, up_row = tab(0xA226, 0xA24C, 38), [m[0xA298 + i] for i in range(38)]
    lower = {}
    issues = []
    for x in range(42):
        msk = lo_m[x] if lo_m[x] >> 8 else None
        key = (lo_s[x], msk, lo_mrow[x] - lo_row[x], lo_mcol[x])
        if key in lower:
            continue
        o, cv = compose(lo_s[x], lo_row[x], 0, msk, lo_mrow[x], lo_mcol[x])
        lower[key] = (o, cv)
        if msk:
            # sprite pixels where the mask keeps the background: drawn over it
            sr, sw, sp = img(lo_s[x])
            mr, mw, mp = img(msk)
            outside = sum(1 for y in range(sr) for xx in range(sw * 4) if sp[y][xx]
                          and not (0 <= xx - lo_mcol[x] * 4 < mw * 4 and 0 <= y - (lo_mrow[x] - lo_row[x]) < mr))
            if outside:
                issues.append("lower %d: %d sprite pixels outside its mask's box" % (x, outside))
        else:
            issues.append("lower %d ($%04X): no mask" % (x, lo_s[x]))
    upper = {u: compose(u, 0, 0) for u in set(up_s)}
    heads = {}
    for name, (slo, shi, mlo, mhi) in {"player": (0xA1CD, 0xA1CA, 0xA1D9, 0xA1D6)}.items():
        for y in range(3):
            s, mk = m[slo + y] | m[shi + y] << 8, m[mlo + y] | m[mhi + y] << 8
            heads[(name, y)] = compose(s, 0, 0, mk, 0, 0)
    for t, (slo, shi) in {0: (0xA1D3, 0xA1D0), 1: (0xA2EB, 0xA2E8), 2: (0xA2F1, 0xA2EE), 3: (0xA2F7, 0xA2F4),
                          4: (0xA2FD, 0xA2FA), 5: (0xAAF6, 0xAAF3), 6: (0xAAFC, 0xAAF9)}.items():
        for y in range(3):
            s = m[slo + y] | m[shi + y] << 8
            mk = m[0xA1D9 + y] | m[0xA1D6 + y] << 8
            if s >> 8:
                heads[("enemy %d" % t, y)] = compose(s, 0, 0, mk, 0, 0)
    stats("lower body (sprite + mask)", list(lower.values()))
    stats("upper body (no mask)", list(upper.values()))
    for who in ["player"] + ["enemy %d" % t for t in range(7)]:
        hp = [v for k, v in heads.items() if k[0] == who]
        if hp:
            stats("head, " + who, hp)
    for i in issues:
        print("  " + i)
    if len(sys.argv) > 1:
        render(sys.argv[1], list(lower.values())[:10] + list(upper.values())[:6] +
               [v for k, v in heads.items()][:8])


def render(path, parts):
    from PIL import Image
    pal = {0: (0, 0, 0), 1: (232, 144, 115), 2: (136, 136, 136), 3: (238, 238, 238), "black": (0, 0, 0)}
    bg = (90, 60, 160)                          # a background that shows what is transparent
    cells = []
    for o, cv in parts:
        xs = [x for x, y in o]
        ys = [y for x, y in o]
        x0, y0, w, h = min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
        a = Image.new("RGB", (w, h), bg)
        b = Image.new("RGB", (w, h), bg)
        for (x, y), v in o.items():
            if v is not None:
                a.putpixel((x - x0, y - y0), pal[v])
        for (x, y), v in cv.items():
            if v is not None:
                b.putpixel((x - x0, y - y0), pal[v])
        cells.append((a, b))
    S = 3
    W = sum(max(a.width, 1) * 2 * S + 3 * S + 4 for a, b in cells[:12])
    H = max(a.height for a, b in cells) * S
    rows = [cells[i:i + 12] for i in range(0, len(cells), 12)]
    out = Image.new("RGB", (max(sum(a.width * 2 * S + 3 * S + 4 for a, b in r) for r in rows), (H + 8) * len(rows)),
                    (255, 255, 255))
    for ri, r in enumerate(rows):
        x = 0
        for a, b in r:
            out.paste(a.resize((a.width * 2 * S // 2 * 1, a.height * S), Image.NEAREST) if False else
                      a.resize((a.width * S, a.height * S), Image.NEAREST), (x, ri * (H + 8)))
            out.paste(b.resize((b.width * S, b.height * S), Image.NEAREST), (x + a.width * S + S, ri * (H + 8)))
            x += a.width * 2 * S + 3 * S + 4
    out.save(path)


if __name__ == "__main__":
    main()
