"""The game's text renderer ($0780) in Python, for pre-rendering its text at
build time: a string is a column, a shift, then characters ($60 + index,
a byte below $60 ends it); each character's glyph (index 0, the space, is
not drawn) comes from the common bank's glyph block ($0480 + the $06F4/$0714
tables: rows, width, then the rows) and is ORed in at the column, shifted
right by shift/2 pixels (the blitter halves $10), all glyphs of a string
hanging from the same top row; the column and shift then advance by the
$0734/$0754 tables, a shift of 8 carrying into the column.

    python probes/storytext.py [dump.bin ...]

Renders the story (strings 4-25 of $7BCC/$7BE6, 14 rows apart, as the scroll
draws them) and, for each original framebuffer dump given (xe-fbdump.lua),
finds the vertical offset where the render matches and reports the bytes
that differ."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import dis as D           # noqa: E402

MEM = D.memory(0)
GLYPH_LO, GLYPH_HI, ADV_COL, ADV_SHIFT, GLYPH_BASE = 0x06F4, 0x0714, 0x0734, 0x0754, 0x0480
STORY_LO, STORY_HI, FIRST, LAST, PITCH = 0x7BCC, 0x7BE6, 4, 25, 14


def glyph(x):
    p = GLYPH_BASE + (MEM[GLYPH_HI + x] << 8 | MEM[GLYPH_LO + x])
    rows, width = MEM[p], MEM[p + 1]
    return rows, width, [MEM[p + 2 + i] for i in range(rows * width)]


def render_string(img, at, top, width=40):
    """OR the string at address `at` into img (a list of bytearrays, `width`
    bytes a row) with its glyphs' top at row `top`."""
    col, shift = MEM[at], MEM[at + 1]
    i = at + 2
    while MEM[i] >= 0x60:
        x = MEM[i] - 0x60
        if x:
            rows, w, data = glyph(x)
            px = shift >> 1
            for r in range(rows):
                if not 0 <= top + r < len(img):
                    continue
                # the row's bits, shifted right by 2*px bits across w+1 bytes
                v = 0
                for b in range(w):
                    v = v << 8 | data[r * w + b]
                v <<= 8
                v >>= 2 * px
                for b in range(w + 1):
                    c = col + b
                    if 0 <= c < width:
                        img[top + r][c] |= (v >> (8 * (w - b))) & 0xFF
        col += MEM[ADV_COL + x]
        shift += MEM[ADV_SHIFT + x]
        if shift >= 8:
            col += 1
            shift -= 8
        i += 1
    return img


def story():
    """The story as one image: 40 bytes a row, the strings PITCH rows apart."""
    n = (LAST - FIRST + 1) * PITCH
    img = [bytearray(40) for _ in range(n)]
    for k in range(FIRST, LAST + 1):
        at = MEM[STORY_HI + k] << 8 | MEM[STORY_LO + k]
        render_string(img, at, (k - FIRST) * PITCH)
    return img


def main():
    img = story()
    used = [max((i for i, v in enumerate(r) if v), default=-1) + 1 for r in img]
    print("story: %d rows, widest row %d bytes; rows with ink: %d" % (
        len(img), max(used), sum(1 for u in used if u)))
    for path in sys.argv[1:]:
        dump = open(path, "rb").read()
        for bi, name in ((0, "A"), (1, "B")):
            buf = [dump[bi * 6120 + r * 40:bi * 6120 + (r + 1) * 40] for r in range(153)]
            best = None
            for off in range(-160, len(img)):
                # buffer row r shows story row r + off
                diff = rows = 0
                for r in range(153):
                    s = r + off
                    if 0 <= s < len(img):
                        rows += 1
                        diff += sum(1 for a, b in zip(buf[r], img[s]) if a != b)
                if rows >= 40 and (best is None or diff < best[0]):
                    best = (diff, off, rows)
            print("%s buffer %s: best offset %d over %d rows, %d bytes differ" % (
                os.path.basename(path), name, best[1], best[2], best[0]))


if __name__ == "__main__":
    main()
