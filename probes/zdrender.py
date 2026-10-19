"""(debug) the band as MARIA would draw it from tmp-zonedump.lua's zonedump.log
and zdram.bin (ZDRAM=1; cart RAM objects only: ROM objects drawn as 'x'):
direct 4-byte headers and indirect (character) 5-byte ones, 160A, colour
indices with the palette's number beside, to PNG.
    python probes/zdrender.py DIR OUT.png [CHBASE] [first line] [last line]"""
import re
import sys
from PIL import Image

PAL = [(0, 0, 0), (230, 150, 120), (110, 160, 240), (240, 240, 240)]


def main():
    d = sys.argv[1]
    out = sys.argv[2]
    chb = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x69
    l0 = int(sys.argv[4]) if len(sys.argv) > 4 else 113
    l1 = int(sys.argv[5]) if len(sys.argv) > 5 else 200
    ram = open(d + "/zdram.bin", "rb").read()

    def m(a):
        return ram[a - 0x4000] if 0x4000 <= a < 0x8000 else None
    im = Image.new("RGB", (160, l1 - l0), (40, 0, 40))
    for ln in open(d + "/zonedump.log"):
        z = re.match(r"zone \d+ lines (\d+)-(\d+) \((\d+)\).*?:(.*)", ln)
        if not z:
            continue
        a, b, h = int(z.group(1)), int(z.group(2)), int(z.group(3))
        if b < l0 or a > l1:
            continue
        for obj in re.findall(r"\[([^\]]*)\]", z.group(4)):
            p = obj.split()
            if p[0].startswith("5:"):
                lo, mode, hi, pw, x = int(p[0][2:], 16), int(p[1], 16), int(p[2], 16), int(p[3], 16), int(p[4], 16)
                ind = mode & 0x20
            else:
                lo, pw, hi, x = int(p[0], 16), int(p[1], 16), int(p[2], 16), int(p[3][1:])
                ind = 0
            w = 32 - (pw & 0x1F)
            for line in range(a, b + 1):
                if not l0 <= line < l1:
                    continue
                off = h - 1 - (line - a)
                bytes_ = []
                if ind:
                    for k in range(w):
                        mb = m(hi * 256 + lo + k)
                        if mb is None:
                            bytes_ += [None, None]
                            continue
                        for q in range(2):
                            bytes_.append(m((chb + off) * 256 + mb + q))
                else:
                    for k in range(w):
                        bytes_.append(m((hi + off) * 256 + lo + k))
                for k, v in enumerate(bytes_):
                    for q in range(4):
                        px = (x + 4 * k + q) & 0xFF
                        if px >= 160:
                            continue
                        if v is None:
                            im.putpixel((px, line - l0), (255, 0, 255))
                            continue
                        c = (v >> (6 - 2 * q)) & 3
                        if c:
                            im.putpixel((px, line - l0), PAL[c])
    im.resize((640, 4 * (l1 - l0)), Image.NEAREST).save(out)


if __name__ == "__main__":
    main()
