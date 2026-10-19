"""Pictures of the fighters as the original draws them and as the planned
MARIA objects would show them (FINDINGS "Keeping colours: heads on the
torso, black as its own layer"): from the original's draw logs, each chosen
picture's actor blits in order on black (a mask clears, a sprite ORs), and
again with the lower body's grey made white (the heads and torsos keep their
colours: the black split off as its own layer changes nothing to look at).

    python probes/renderfighters.py work/analysis/bl-s1 out.png [N]
N pictures (default 8), spread through the run, original above, planned
below."""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import workingset as W     # noqa: E402

LOWER_SPRITES = {"A863", "A8EB"}          # bank 15's lower-body sprite blits
PAL = {0: (0, 0, 0), 1: (232, 144, 115), 2: (136, 136, 136), 3: (238, 238, 238)}


def draw(sc, blits, planned):
    canvas = {}
    for kind, src, col, top, shift, mode, caller in blits:
        px = W.pixels(sc, kind, src, col, top, shift, mode)
        for xy, v in px.items():
            if mode < 0:
                canvas[xy] = 0
            else:
                if planned and caller in LOWER_SPRITES and v == 2:
                    v = 3
                canvas[xy] = canvas.get(xy, 0) | v if not planned else v
    return canvas


def main():
    d, out = sys.argv[1], sys.argv[2]
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    want = int(d.rstrip("/").split("bl-s")[-1])
    pics = {}
    for line in open(os.path.join(d, "bandlog.log")):
        t = line.split()
        if t[0] != "B" or int(t[3]) != want:
            continue
        f, flip, sc, kind, src, bank, rows, width, caller, col, top, shift, mode, buf = t[1:]
        if caller not in W.ACTOR_CALLERS.get(want, ()):
            continue
        pics.setdefault((int(flip), buf), []).append((kind, int(src, 16), int(col), int(top), int(shift),
                                                      int(mode), caller))
    keys = sorted(pics)
    chosen = [keys[i * len(keys) // n] for i in range(n)]
    S, x0, x1, y0, y1 = 3, 0, 160, 75, 135
    img = Image.new("RGB", ((x1 - x0) * S * n // 2 + 4 * (n // 2), (y1 - y0) * S * 4 + 12), (60, 0, 60))
    for i, k in enumerate(chosen):
        for j, planned in enumerate((False, True)):
            c = draw(want, pics[k], planned)
            tile = Image.new("RGB", (x1 - x0, y1 - y0), (0, 0, 0))
            for (x, y), v in c.items():
                if x0 <= x < x1 and y0 <= y < y1:
                    tile.putpixel((x - x0, y - y0), PAL[v])
            tile = tile.resize((tile.width * S, tile.height * S), Image.NEAREST)
            col, row = i % (n // 2), (i // (n // 2)) * 2 + j
            img.paste(tile, (col * (tile.width + 4), row * (tile.height + 3)))
    img.save(out)
    print("pictures", chosen)


if __name__ == "__main__":
    main()
