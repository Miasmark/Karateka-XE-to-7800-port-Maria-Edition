"""A BankSet test cart: what MARIA reads, and whether cart RAM is shared.

Two 2 x 128K SuperGame BankSet images that differ only in the header:
  work/bankset-test-shared.a78  type $2006: BankSet, RAM at $4000, SuperGame
  work/bankset-test-spec.a78    type $6002: BankSet, BankSet RAM, SuperGame
The code runs from the CPU half's fixed bank, the display lists are in console
RAM (the spec's rules: FINDINGS "More ROM for MARIA"). Five bars, top down,
on black:
  1  white solid        console RAM: the control, always there
  2  white solid        $E000 (MARIA's fixed bank). White stripes: MARIA read
                        the CPU's half (no BankSet)
  3  white bar, 4 bytes $8000 (the window, CPU on bank 3): MARIA's half has a
                        bar of bank+1 bytes in each bank, so its length says
                        which bank MARIA reads. Stripes: the CPU's half
  4  red                cart RAM the CPU wrote at $4000: the RAM is shared
  5  green              cart RAM written through $C800: MARIA's own RAM, as
                        the spec has it
Expected: shared header on a cart that shares RAM: 1, 2, 3, 4. The spec
header: 1, 2, 3, 5.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import xesource          # noqa: E402,F401  (puts the toolkit's tools on the path)
import asm               # noqa: E402
import sign7800          # noqa: E402

BANK = 0x4000
STRIPES, SOLID = 0xCC, 0xFF

CODE = """
INPTCTRL = $01
BACKGRND = $20
P0C1 = $21
P0C2 = $22
P0C3 = $23
DPPH = $2C
DPPL = $30
OFFSET = $38
CTRL = $3C
PTR = $80
PAGE = $82
VAL = $84
    .org $F000
Reset:
    SEI
    CLD
    LDA #$07
    STA INPTCTRL
    LDA #$7F
    STA CTRL
    LDX #$FF
    TXS
    LDA #$00
    STA BACKGRND
    STA OFFSET
    LDA #$34
    STA P0C1
    LDA #$C8
    STA P0C2
    LDA #$0F
    STA P0C3
    LDX #$00
CopyLists:
    LDA DLLTAB,X
    STA $1800,X
    LDA DLTAB,X
    STA $1900,X
    INX
    BNE CopyLists
    LDA #$20
    STA PAGE
    LDA #$FF
    JSR Fill
    LDA #$C0
    STA PAGE
    LDA #$00
    JSR Fill
    LDA #$C8
    STA PAGE
    LDA #$00
    JSR Fill
    LDA #$40
    STA PAGE
    LDA #$55
    JSR Fill
    LDA #$48
    STA PAGE
    LDA #$00
    JSR Fill
    LDA #$C8
    STA PAGE
    LDA #$AA
    JSR Fill
    LDA #$03
    STA $8000
    LDA #$18
    STA DPPH
    LDA #$00
    STA DPPL
    LDA #$40
    STA CTRL
Forever:
    JMP Forever
Fill:
    STA VAL
    LDA #$00
    STA PTR
    LDA PAGE
    STA PTR+1
    LDX #$08
Fill1:
    LDY #$07
    LDA VAL
Fill2:
    STA (PTR),Y
    DEY
    BPL Fill2
    INC PTR+1
    DEX
    BNE Fill1
    RTS
Nmi:
Irq:
    RTI
"""


def lists():
    """the DLL ($1800) and the display lists ($1900): an empty list, then
    one list a bar (one 8-byte object, palette 0, at hpos 40)"""
    bars = [0x20, 0xE0, 0x80, 0x40, 0x48]           # each bar's first page
    dl = bytearray(256)
    for i, hi in enumerate(bars):
        at = 0x10 + 8 * i
        dl[at:at + 6] = bytes([0x00, (-8) & 0x1F, hi, 40, 0x00, 0x00])
    dll = bytearray()
    for _ in range(2):
        dll += bytes([0x0F, 0x19, 0x00])            # 16 blank lines
    for i in range(len(bars)):
        dll += bytes([0x07, 0x19, 0x10 + 8 * i])    # the bar, 8 lines
        dll += bytes([0x07, 0x19, 0x00])            # 8 blank lines
    while len(dll) < 3 * 24:
        dll += bytes([0x0F, 0x19, 0x00])
    return bytes(dll.ljust(256, b"\0")), bytes(dl)


def put8(img, base, page, data):
    """data (8 bytes) at offsets 0-7 of pages page..page+7 of an image based at base"""
    for line in range(8):
        a = (page + line) * 256 - base
        img[a:a + 8] = data


def build(out_dir):
    dll, dl = lists()
    cpu = [bytearray(BANK) for _ in range(8)]
    maria = [bytearray(BANK) for _ in range(8)]
    for b in range(7):
        put8(cpu[b], 0x8000, 0x80, bytes([STRIPES] * 8))
        put8(maria[b], 0x8000, 0x80, bytes([SOLID] * (b + 1) + [0] * (7 - b)))
    put8(cpu[7], 0xC000, 0xE0, bytes([STRIPES] * 8))
    put8(maria[7], 0xC000, 0xE0, bytes([SOLID] * 8))
    fx = cpu[7]
    # the tables the code copies: the two pages after the code ($F400: the code is short)
    tab_at = 0xF400
    a = asm.Assembler()
    code = a.assemble(["DLLTAB = $%04X" % tab_at, "DLTAB = $%04X" % (tab_at + 256)]
                      + [ln for ln in CODE.splitlines()])
    sym = a.sym
    if 0xF000 + len(code) > tab_at:
        raise SystemExit("the code runs into its tables")
    fx[0xF000 - 0xC000:0xF000 - 0xC000 + len(code)] = code
    fx[tab_at - 0xC000:tab_at - 0xC000 + 256] = dll
    fx[tab_at + 256 - 0xC000:tab_at + 512 - 0xC000] = dl
    fx[0xFFF8 - 0xC000:0xFFFA - 0xC000] = bytes([0xFF, 0xC7])
    fx[0xFFFA - 0xC000:0x10000 - 0xC000] = bytes([sym["Nmi"] & 0xFF, sym["Nmi"] >> 8,
                                                   sym["Reset"] & 0xFF, sym["Reset"] >> 8,
                                                   sym["Irq"] & 0xFF, sym["Irq"] >> 8])
    cpu_half = sign7800.signed(b"".join(bytes(x) for x in cpu))
    maria_half = b"".join(bytes(x) for x in maria)
    rom = cpu_half + maria_half
    for name, ctype in (("bankset-test-shared.a78", 0x2006), ("bankset-test-spec.a78", 0x6002)):
        hdr = bytearray(128)
        hdr[0] = 3
        hdr[1:10] = b"ATARI7800"
        hdr[17:17 + 20] = b"BankSet RAM test".ljust(20, b"\0")
        hdr[49:53] = len(rom).to_bytes(4, "big")
        hdr[53:55] = ctype.to_bytes(2, "big")
        hdr[55] = hdr[56] = 1
        hdr[100:128] = b"ACTUAL CART DATA STARTS HERE"
        with open(os.path.join(out_dir, name), "wb") as f:
            f.write(bytes(hdr) + rom)
        print("wrote %s (%d bytes, type $%04X)" % (name, 128 + len(rom), ctype))


if __name__ == "__main__":
    build(os.path.join(HERE, "..", "work"))
