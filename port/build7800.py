#!/usr/bin/env python3
"""
Build the 7800 cartridge of XEGS Karateka, MARIA Edition: a 2 x 128K BankSet
cartridge (the CPU's half, then MARIA's), signed.

    python port/build7800.py --car Karateka.car             v1 -> work/karateka7800.a78
    python port/build7800.py --car Karateka.car --v2        V2 -> work/v2/karateka7800.a78

v1 (header $2006): one 16K of cartridge RAM at $4000, shared by both halves;
each scene's tiles, fighter slices and poses are written there at its load.
V2 (header $2002, also V2=1 in the environment): no cartridge RAM; bank 6 of
each half is fixed at $4000, each scene's code and graphics are on its own
page, and play needs no bank switch. port/layout7800.py has the memory map;
FINDINGS.md the reasons ("The ROM by scene").

Every byte of the cartridge is placed through one map that refuses overlaps.
The result contains cartridge data: it goes under work/ (ignored), never
into the repository.
"""
import argparse
import glob
import json
import re
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if "--v2" in sys.argv[1:]:
    os.environ["V2"] = "1"       # (before layout7800 reads it)
sys.path.insert(0, HERE)
import link7800 as K     # noqa: E402
import layout7800 as L   # noqa: E402
import dis as D          # noqa: E402
import fuji7800 as FJ    # noqa: E402
import fighters7800 as F  # noqa: E402
import titlemaria7800 as TM  # noqa: E402
import l1scene7800 as LS      # noqa: E402
import l1world7800 as LW      # noqa: E402
import akpose7800 as AK       # noqa: E402
import asm               # noqa: E402
import sign7800          # noqa: E402  (the toolkit's, on the path via xesource)

BANK = 0x4000
SP_RESERVE = 0x2C8 if L.V2 else 0x200   # (the scene pages' system code's room: V2 up to the common code, $96E8)
FBA_BASE, FBB_BASE = 0x5808, 0x4010     # row 0 of each buffer on the 7800
ROWS = 153
DLL_LINES = 243
SPRITE_TAIL = (0x06E8, 0x06F6)   # the hyphen glyph after the small-sprite block
SND_OFFSET = 0               # the TIA music's transposition in cents (port/sndconv.py)
SMALL_DLS = 0xF8B4              # the empty and mode-8 row DLs, in a sprite-copy gap
VBI_LINE = DLL_LINES - 2   # the line whose DLI stands in for the vertical blank
VBI_MARGIN = 16            # lines every list's last DLI must leave before VBI_LINE
GAME_DLIS = 6              # every XEGS list has six DLIs; the NMI count relies on it
BLANK_DLIS = (31, 85, 126, 137, 180, 193)   # the blank list's dummy DLIs, at the
                                            # lines most game lists use
SIG_START = 0xFF80          # $FF80-$FFF7: the NTSC signature, written by the signer
                            # after everything is placed; free-space searches stop here
VBI_SPIN = 110             # turns of an 11-cycle loop the vertical blank waits for
# instructions the patch kit's options edit (port/mkkit.py; FINDINGS, "A build
# without MAME"), as XEGS addresses and the scenes whose banks hold them; the
# build writes their 7800 addresses to karateka7800.sites.json. Scene 0 (the
# title and attract sequence) is left alone throughout, as xe-easy.lua does.
PATCH_SITES = [      # (name, XEGS label, offset from it, scenes)
    ("player-damage", 0x0BDD, 8, (1, 2, 3, 4, 6)),   # DEC $B6 / BNE $0BED
    ("foe-damage", 0x0BEE, 8, (1, 2, 3, 4, 6)),      # DEC $B7 / BNE $0BFE
    ("instant-death", 0xB12A, 4, (1,)),              # BEQ $B131 (bank 15, shared)
    ("gate", 0x79C5, 0, (2,)),                       # LDA $A7 (is the gate low enough)
    ("cliff", 0x7914, 0, (1, 6)),                    # LDA $A2 (driven over the edge)
    ("game-start", 0x7806, 1, (0,)),                 # LDA #$01 / STA $D0: the first scene
]
                           # MSTAT (about 10 lines; it needs about 2)
PAL = 1                                  # the palette COLPF0-2 are mapped to
HW = {"INPTCTRL": 0x01, "AUDC0": 0x15, "AUDC1": 0x16, "AUDF0": 0x17, "AUDF1": 0x18,
      "AUDV0": 0x19, "AUDV1": 0x1A, "BACKGRND": 0x20, "WSYNC": 0x24,
      "MSTAT": 0x28, "DPPH": 0x2C, "DPPL": 0x30, "M_CHBASE": 0x34, "CTRL": 0x3C, "SWCHA": 0x280,
      "SWCHB": 0x282, "CTLSWA": 0x281, "CTLSWB": 0x283, "INPT0": 0x08, "INPT1": 0x09, "INPT4": 0x0C,
      "BANKSEL": 0x8000}
SP = {"SP_ENGINE7": 0x8000, "SP_NCARVE": 0x8007, "SP_CARVE": 0x8008,
      "SP_NDL": 0x8040, "DLT_LO": 0x8041, "DLT_HI": 0x8049, "DLT_BUF": 0x8051,
      "DLT_CTRL": 0x8059, "DLT_DLO": 0x8061, "DLT_DHI": 0x8069, "DLT_M8": 0x8071,
      "SP_DESC": 0x8080}
IMG = {"IMG_ENGINE2": 0xA000, "IMG_SPRITES": 0xAD00}   # in L.IMG_BANK
if L.V2:                     # (V2: IMG_BANK is bank 6, at $4000)
    IMG = {k: v - 0x4000 for k, v in IMG.items()}
# Akuma's and the hawk's poses: the search, in the tables' bank (FARL4: AkLook
# calls it through L1Call): the set's table (AKP_P) walked for the key
# (AKP_KEY), its cells to AKP_T/C and AKP_ON 1, else AKP_ON 0; ZP_P2 kept
AKFIND = """
;;; FARL4 (AkFindP)
AkFind:
    LDA ZP_P2
    PHA
    LDA ZP_P2+1
    PHA
    LDA AKP_P
    STA ZP_P2
    LDA AKP_P+1
    STA ZP_P2+1
AkF0:
    LDY #$00
    LDA (ZP_P2),Y
    STA AKP_N
    INY
    LDA (ZP_P2),Y
    STA AKP_P
    INY
    LDA (ZP_P2),Y
    STA AKP_P+1
    LDA ZP_P2
    CLC
    ADC #$03
    STA ZP_P2
    BCC AkF1
    INC ZP_P2+1
AkF1:
    LDA AKP_N
    BNE AkF2
    LDA AKP_P+1
    BEQ AkFNo
    STA ZP_P2+1
    LDA AKP_P
    STA ZP_P2
    JMP AkF0
AkF2:
    DEC AKP_N
    LDY #$00
AkF3:
    LDA (ZP_P2),Y
    CMP AKP_KEY,Y
    BNE AkFN
    INY
    CPY #$06
    BNE AkF3
    LDY #AKP_NOFF
    LDA (ZP_P2),Y
    STA AKP_SB+1
    LDX #$00
AkF4:
    CPX AKP_SB+1
    BCS AkF5
    INY
    LDA (ZP_P2),Y
    STA AKP_T,X
    INY
    LDA (ZP_P2),Y
    STA AKP_C,X
    INX
    BNE AkF4
AkF5:
    LDA #$01
    STA AKP_ON
    BNE AkFOut
AkFN:
    LDY #AKP_NOFF
    LDA (ZP_P2),Y
    ASL A
    CLC
    ADC #AKP_NOFF+1
    CLC
    ADC ZP_P2
    STA ZP_P2
    BCC AkF1
    INC ZP_P2+1
    JMP AkF1
AkFNo:
    LDA #$00
    STA AKP_ON
AkFOut:
    PLA
    STA ZP_P2+1
    PLA
    STA ZP_P2
    RTS
"""


def v_filter(text):
    """the source for this build's layout (layout7800.V2): a line tagged
    "; #V1" only in today's, "; #V2" only in the new one (FINDINGS "The ROM
    by scene: step 3")"""
    out = []
    for ln in text.split("\n"):
        if re.search(r"#V1\b", ln) and L.V2:
            continue
        if re.search(r"#V2\b", ln) and not L.V2:
            continue
        out.append(ln)
    return "\n".join(out)


_BR = re.compile(r"^(?:[A-Za-z_]\w*:)?\s+(BCC|BCS|BEQ|BNE|BMI|BPL|BVC|BVS)\s+([A-Za-z_]\w*)\s*$")
_UNC = re.compile(r"^(?:[A-Za-z_]\w*:)?\s+(JMP|RTS|RTI)\b")
_LAB = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):")


def split_parts(lines):
    """a piece's lines cut into parts that each stand alone: at a label after
    a JMP, RTS or RTI (nothing falls into it) where no relative branch
    crosses; the parts reach each other by JMP and JSR only, so each may go
    anywhere (V2's per-page copies, FARPG: the pages' runs are short)"""
    code = [ln.split(";")[0].rstrip() for ln in lines]
    where = {m.group(1): i for i, c in enumerate(code) for m in [_LAB.match(c)] if m}
    spans = [(min(i, where[m.group(2)]), max(i, where[m.group(2)]))
             for i, c in enumerate(code) for m in [_BR.match(c)] if m and m.group(2) in where]
    cuts, last_unc = [], False
    for i, c in enumerate(code):
        if _LAB.match(c) and last_unc and i > 0 and not any(lo < i <= hi for lo, hi in spans):
            cuts.append(i)
        if _LAB.match(c):           # (a label runs on into what follows it: the next
            last_unc = False        # label is no cut, even if this one was)
        body = _LAB.sub("", c).strip()
        if body:
            last_unc = bool(_UNC.match("    " + body))
    bounds = [0] + cuts + [len(lines)]
    return [lines[bounds[k]:bounds[k + 1]] for k in range(len(bounds) - 1)]


_INV = {"BCC": "BCS", "BCS": "BCC", "BEQ": "BNE", "BNE": "BEQ", "BMI": "BPL", "BPL": "BMI", "BVC": "BVS", "BVS": "BVC"}
_cutn = [0]


PG_MAKE = False       # (and straight code cut by a JMP of its own where it must)
AKP_TO_FIXED = 80      # (V2: bank 4's poses' tables up to this many bytes in the fixed bank's room: the
                       # release's keeps leave bank 4 short for its per-page copies; the tables are
                       # chained by pointers, the fixed bank always in; FINDINGS "The V2 release audit")
PG_MAXLINES = 18      # (V2's per-page copies: parts this long at most where a cut is cheap; bank 4's
                      # free runs are ~25 bytes: FINDINGS "The music's records released")
PG_HOLD = ()            # (V2: the banks whose per-page parts are held first: "The hardware test")
PG_MAXLINES_BY_BANK = {}   # (bank 4's runs ~10 bytes since Akuma's cells are 160B:
                               # FINDINGS "Akuma's red")


def split_long(lines, maxlines=24, make=False):
    """split_parts, and a part longer than maxlines cut once more where it
    costs least: at a label after a JMP, RTS or RTI near its middle, each
    relative branch across the cut made an inverted branch over a JMP (3
    bytes); again till none is longer (V2's per-page copies: scene 4's page's
    runs are at most 266 bytes). make: straight code cut too, by a JMP of
    its own (the loader's pieces; the per-page copies don't need it, and
    each made cut costs every page its 3 bytes)"""
    out = []
    for pt in split_parts(lines):
        if len(pt) <= maxlines:
            out.append(pt)
            continue
        code = [ln.split(";")[0].rstrip() for ln in pt]
        where = {m.group(1): i for i, c in enumerate(code) for m in [_LAB.match(c)] if m}
        brs = [(i, m.group(1), m.group(2)) for i, c in enumerate(code) for m in [_BR.match(c)] if m and m.group(2) in where]
        best, last_unc = None, False
        for i, c in enumerate(code):
            if _LAB.match(c) and last_unc and len(pt) // 5 < i < len(pt) - len(pt) // 5:
                cross = [b for b in brs if min(b[0], where[b[2]]) < i <= max(b[0], where[b[2]])]
                cost = len(cross) * len(pt) + abs(i - len(pt) // 2)
                if best is None or cost < best[0]:
                    best = (cost, i, cross)
            if _LAB.match(c):
                last_unc = False
            body = _LAB.sub("", c).strip()
            if body:
                last_unc = bool(_UNC.match("    " + body))
        made = None
        if best is None and not make:
            out.append(pt)          # (no cut: as it is)
            continue
        if best is None:                # (straight code: a cut made, JMP to a label of its own at an
            for i, c in enumerate(code):        # instruction near the middle; a JMP keeps A, X, Y and the flags)
                body = _LAB.sub("", c).strip()
                if not (len(pt) // 5 < i < len(pt) - len(pt) // 5) or not body or body.startswith("."):
                    continue
                cross = [b for b in brs if min(b[0], where[b[2]]) < i <= max(b[0], where[b[2]])]
                cost = len(cross) * len(pt) + abs(i - len(pt) // 2)
                if made is None or cost < made[0]:
                    made = (cost, i, cross)
            if made is None:
                out.append(pt)          # (no cut at all: as it is)
                continue
            _cutn[0] += 1
            jl = "SplitJ%d" % _cutn[0]
            i = made[1]
            pt = pt[:i] + ["    JMP %s" % jl, "%s:" % jl] + pt[i:]
            out += split_long(pt, maxlines, make)     # (the new label after the JMP: an ordinary cut now)
            continue
        cost, cut, cross = best
        # (a branch over one made long grows by its 3 bytes: a long one,
        # 40 lines or more, made long too, till none is left)
        conv = {b[0] for b in cross}
        while True:
            more = {b[0] for b in brs if b[0] not in conv and abs(where[b[2]] - b[0]) >= 40
                    and any(min(b[0], where[b[2]]) < c <= max(b[0], where[b[2]]) for c in conv)}
            if not more:
                break
            conv |= more
        cross = [b for b in brs if b[0] in conv]
        new = list(pt)
        for bi, op, tgt in sorted(cross, reverse=True):     # (from the end: indexes hold)
            _cutn[0] += 1
            sk = "SplitSk%d" % _cutn[0]
            lab = _LAB.match(code[bi])
            new[bi:bi + 1] = (([lab.group(0)] if lab else []) +
                              ["    %s %s" % (_INV[op], sk), "    JMP %s" % tgt, "%s:" % sk])
            if bi < cut:
                cut += 2 + (1 if lab else 0)
        out += split_long(new[:cut], maxlines, make) + split_long(new[cut:], maxlines, make)
    return out


_LEN1 = {0x00, 0x08, 0x18, 0x28, 0x38, 0x40, 0x48, 0x58, 0x60, 0x68, 0x78, 0x88, 0x8A, 0x98, 0x9A, 0xA8,
         0xAA, 0xB8, 0xBA, 0xC8, 0xCA, 0xD8, 0xE8, 0xEA, 0xF8, 0x0A, 0x2A, 0x4A, 0x6A}


def oplen(op):
    """a 6502 instruction's length from its opcode (probes/romplan.py's)"""
    if op in _LEN1:
        return 1
    if op in (0x20, 0x4C, 0x6C):
        return 3
    cc, bbb = op & 3, (op >> 2) & 7
    if cc == 1:
        return 3 if bbb in (3, 6, 7) else 2
    return 3 if bbb in (3, 7) else 2


class Image(object):
    """One 16K bank; place() refuses to overwrite anything placed before."""

    def __init__(self, name, base):
        self.name, self.base = name, base
        self.data = bytearray([0xFF]) * BANK
        self.used = bytearray(BANK)
        self.log = []                        # (address, bytes, what): the bank's map

    def place(self, addr, data, what):
        off = addr - self.base
        if off < 0 or off + len(data) > BANK:
            raise SystemExit("%s: %s ($%04X, %d bytes) outside the bank" % (self.name, what, addr, len(data)))
        for i in range(len(data)):
            if self.used[off + i]:
                raise SystemExit("%s: %s overlaps something at $%04X" % (self.name, what, addr + i))
        self.data[off:off + len(data)] = data
        for i in range(len(data)):
            self.used[off + i] = 1
        self.log.append((addr, len(data), what))

    def release(self, addr, n, what):
        """Give back n bytes placed before: free again (FF)."""
        off = addr - self.base
        self.data[off:off + n] = bytes([0xFF]) * n
        self.used[off:off + n] = bytes(n)
        self.log.append((addr, -n, what))

    def find(self, size, lo, hi):
        """The lowest free run of `size` bytes in [lo, hi), or None. (A
        window range, $8000-$C000, is the bank's own 16K: bank 6 is at $4000
        in V2.)"""
        if self.base == 0x4000 and 0x8000 <= lo < hi <= 0xC000:
            lo, hi = lo - 0x4000, hi - 0x4000
        run = 0
        for a in range(lo, hi):
            run = 0 if self.used[a - self.base] else run + 1
            if run == size:
                return a - size + 1
        return None


# ------------------------------------------------------- display lists
FB_PTOP, FB_PBOT, FB_BAND = L.FB_PTOP, L.FB_PBOT, L.FB_BAND
DL_W = (PAL << 5) | ((-20) & 0x1F)      # a 20-byte object in the bitmap's palette
fb_row = L.fb_row


def zones(d, band):
    """(DLL entries, row-zone display lists in DLS_A/B, band zone lists) the
    zone builder makes for a run list, as sys7800.asm BuildDll does: band
    True with the title off (the actors' rows' zones on the BAND_ZH grid, in
    their own lists), False with it up"""
    entries = dls = bands = lines = 0
    for i in range(0, len(d) - 1, 3):
        k, n, arg = d[i], d[i + 1], d[i + 2]
        flag = 1 if k & 0x80 else 0
        n -= flag
        if k & 0x3F == 0:
            entries += (n + 15) // 16 + flag
        elif k & 0x3F == 1:
            entries += n + flag
        else:
            r = arg
            while n:
                if r >= L.FB_ROWS:          # the status rows and below: not the buffer's
                    h = min(16, n)
                elif r < L.FB_TOP:          # the top rows: objects, on the TOP_ZONE grid
                    h = min(16, n, L.TOP_ZONE - r % L.TOP_ZONE, L.FB_TOP - r)
                else:
                    zh = L.BAND_ZH - (r - L.FB_TOP) % FB_BAND % L.BAND_ZH if band and r <= L.BAND_ZEND else 16
                    h = min(zh, n, FB_BAND - (r - L.FB_TOP) % FB_BAND, L.FB_ROWS - r)
                entries += 1
                if band and L.FB_TOP <= r <= L.BAND_ZEND:
                    bands += 1
                else:
                    dls += 1
                r += h
                n -= h
            entries += flag
            if flag and band and L.FB_TOP <= r <= L.BAND_ZEND:
                bands += 1
            else:
                dls += flag
        lines += d[i + 1]
    entries += (VBI_LINE - lines + 15) // 16 + 1 + (DLL_LINES - VBI_LINE - 1 + 15) // 16
    return entries, dls, bands


def row_dl(base, r):
    a = base + 40 * r
    b = a + 20
    w = (PAL << 5) | ((-20) & 0x1F)
    return bytes([a & 0xFF, w, a >> 8, 0x00, b & 0xFF, w, b >> 8, 80, 0x00, 0x00])


def xe_display_lists():
    """{scene: set of XEGS display list addresses the game selected}."""
    used = {}
    lists = os.path.join(K.CENSUS, "xe-display-lists.txt")
    if os.path.exists(lists):     # (port/mkcensus.py's digest of the .col files)
        for line in open(lists):
            if line.strip() and not line.startswith("#"):
                s, a = line.split()
                used.setdefault(int(s), set()).add(int(a, 16))
        return used
    for p in glob.glob(os.path.join(K.CENSUS, "*.col")):
        lo = None
        for line in open(p):
            parts = line.split()
            if len(parts) < 5:
                continue
            s, reg, val = int(parts[0]), parts[3], int(parts[4], 16)
            if reg == "D402":
                lo = val
            elif reg == "D403" and lo is not None:
                used.setdefault(s, set()).add(val * 256 + lo)
    return used


def list_fits(mem, at):
    """This scene holds a list at `at` the port can show: it parses, has the
    game's six DLIs, and ends above the vertical blank stand-in."""
    try:
        d = describe(mem, at)[0]
    except SystemExit:
        return False
    dls, line = dli_lines(d)
    last_dli = max(dls or [-1])
    ndli = len(dls)
    return ndli == GAME_DLIS and line <= VBI_LINE and last_dli <= VBI_LINE - VBI_MARGIN


def shared_display_lists(used, mems):
    """The census lists, plus every list another scene's census saw that
    this scene also holds as a valid list (its own version of it, which may
    differ: scene 0's $19B3 has a DLI ten lines lower than scene 1's). Paths
    no census run took use them: scene 0's attract sequence shows $19B3 after
    the cutscene, and without it the port showed the blank list on those
    frames (FINDINGS "Flashing black after the story")."""
    out = {s: set(v) for s, v in used.items()}
    every = set().union(*used.values())
    for s in used:
        for at in every - out[s]:
            if list_fits(mems[s], at):
                out[s].add(at)
    return out


def describe(mem, at):
    """An XEGS display list as runs: (kind|DLI, lines, argument), plus which
    buffer, whether it is mode F (320A) and whether it has mode-8 rows."""
    runs, pc, addr, buf, modef, m8 = [], at, 0, None, False, False
    m8row = 0
    for _ in range(400):
        ins = mem.get(pc, 0)
        mode, dli, lms = ins & 0x0F, bool(ins & 0x80), bool(ins & 0x40)
        if mode == 0:
            runs.append([0, ((ins >> 4) & 7) + 1, 0, dli])
            pc += 1
            continue
        if mode == 1:
            break
        if lms:
            addr = mem.get(pc + 1, 0) | mem.get(pc + 2, 0) << 8
            pc += 3
        else:
            pc += 1
        b = "A" if 0x4800 <= addr < 0x6000 else ("B" if 0x3000 <= addr < 0x4800 else None)
        if b is None:
            raise SystemExit("display list $%04X shows $%04X, not a framebuffer" % (at, addr))
        if buf and b != buf:
            raise SystemExit("display list $%04X mixes buffers" % at)
        buf = b
        if mode == 0x8:
            runs.append([1, 8, m8row, dli])
            m8row += 1
            m8 = True
            addr += 10
        elif mode in (0xE, 0xF):
            row = (addr - (0x4808 if b == "A" else 0x3010)) // 40
            if runs and runs[-1][0] == 2 and not runs[-1][3] and runs[-1][2] + runs[-1][1] == row:
                runs[-1][1] += 1
                runs[-1][3] = dli
            else:
                runs.append([2, 1, row, dli])
            modef = modef or mode == 0xF
            addr += 40
        else:
            raise SystemExit("display list $%04X: ANTIC mode %X not handled" % (at, mode))
    out = bytearray()
    for kind, n, arg, dli in runs:
        out += bytes([kind | (0x80 if dli else 0), n, arg])
    out.append(0xFF)
    return bytes(out), buf, modef, m8


# The game's DLI handler ($1026, engine1) works by its count in the frame:
# the third and sixth DLIs set the colours ($25-$28; the sixth blacks out the
# status bar's), the other four run the music driver, and on a tick that takes
# about 11 lines in MAME. The port runs one DLI at a time (they share save
# bytes), so where a music DLI comes just above a colour one (scene 0's
# lists: 3 lines; the others: 13), a long tick held the colours back past the
# line they are for: the floor's pixels in the first status row showed in the
# floor's grey, every fourth frame (FINDINGS "Late colours"). The music DLIs
# change nothing on screen, so each one closer than DLI_GAP lines above a
# colour DLI is moved up to DLI_GAP lines above it, or just below the DLI
# before it (its run split there); the colour DLIs stay on the game's lines.
# 28 lines: about midway between its neighbours in every list, with room for
# hardware that runs the handler slower than MAME.
COLOUR_DLIS = (2, 5)
DLI_GAP = 28
DLI_NEAR = 12                           # (a music tick's 11 lines)
DLI_FIRST = 0x40                        # a run's kind: the DLI on its first line


def space_dlis(d):
    runs = [list(d[i:i + 3]) for i in range(0, len(d) - 1, 3)]
    for _ in range(2):
        # the line each run ends on, and the DLIs in order
        ends, line = [], 0
        for r in runs:
            line += r[1]
            ends.append(line - 1)
        dlis = [i for i, r in enumerate(runs) if r[0] & 0x80]
        for k, ri in enumerate(dlis):
            if k + 1 not in COLOUR_DLIS or k + 1 >= len(dlis):
                continue
            nxt = ends[dlis[k + 1]]
            want = nxt - DLI_GAP
            prev = ends[dlis[k - 1]] if k else -1
            want = max(want, prev + 1)
            if ends[ri] <= want:
                continue
            # split the run holding line `want` after it: the DLI goes on its first part
            start = 0
            for j, r in enumerate(runs):
                if start <= want < start + r[1]:
                    break
                start += r[1]
            r = runs[j]
            first = want - start + 1
            kind = r[0] & 0x7F
            arg2 = r[2] + first if kind == 2 else r[2]
            head = [kind | 0x80, first, r[2]]
            tail = [kind, r[1] - first, arg2]
            runs[ri][0] &= 0x7F                 # the DLI leaves its old line
            if j == ri:
                tail[0] = kind                  # (the run that had it)
            runs[j:j + 1] = [head] + ([tail] if tail[1] else [])
            break                               # positions moved: again from the top
    # a music DLI on an empty line (blank or mode-8 lines, which BuildDll
    # merges into zones of up to 16) moves on to the next line that is a
    # multiple of 8, if the lines up to it are empty too: its zone then
    # starts on the 8-line grid (MARIA loses 8 cycles at every zone's end,
    # drawn or not: level 1's line 31 left line 47 a zone of its own)
    moved = True
    while moved:
        moved = False
        ends, line = [], 0
        for r in runs:
            line += r[1]
            ends.append(line - 1)
        dlis = [i for i, r in enumerate(runs) if r[0] & 0x80]
        for k, ri in enumerate(dlis):
            at = ends[ri]
            if k in COLOUR_DLIS or runs[ri][0] & 0x7F not in (0, 1) or at % 8 == 0:
                continue
            nxt = ends[dlis[k + 1]] if k + 1 < len(dlis) else line
            prv = ends[dlis[k - 1]] if k else -DLI_NEAR
            # (or back to the multiple of 8 above it: scenes 3 and 4's line
            # 84 left lines 80-83 a zone)
            for target in ((at | 7) + 1, at & ~7):
                if target > nxt - (DLI_GAP if k + 1 in COLOUR_DLIS else 4) or target < prv + DLI_NEAR:
                    continue
                start, j = 0, None
                for jj, r in enumerate(runs):
                    if start <= target < start + r[1]:
                        j = jj
                        break
                    start += r[1]
                if j is None or any(runs[x][0] & 0x7F not in (0, 1) or (x != ri and runs[x][0] & 0x80)
                                    for x in range(min(ri, j), max(ri, j) + 1)):
                    continue
                break
            else:
                continue
            r = runs[j]
            first = target - start + 1
            kind = r[0] & 0x7F
            head = [kind | 0x80, first, r[2]]
            tail = [kind, r[1] - first, r[2]]
            runs[ri][0] &= 0x7F
            runs[j:j + 1] = [head] + ([tail] if tail[1] else [])
            moved = True
            break
    # line by line: [kind, row (buffer rows) or argument, a DLI as the line
    # starts]
    lines = []
    for k, n, a in runs:
        kind = k & 0x3F
        for j in range(n):
            lines.append([kind, a + j if kind == 2 else a, bool(k & 0x40 and j == 0 or k & 0x80 and j == n - 1)])
    # a DLI on buffer rows goes on the first row of a zone of its own
    # (DLI_FIRST), not on a one-line zone (the XE's on a run's last line: as
    # MARIA raises it as the zone starts, BuildDll made that line a zone, and
    # by the grid the rows round it often more: level 1's rows 116-118 three
    # zones of one line; MARIA loses 8 cycles at every zone's end). The colour
    # DLIs keep their lines; a music DLI goes to the nearest row that begins a
    # grid zone (a TOP_ZONE one in the top, a BAND_ZH one in a column to
    # BAND_ZEND), DLI_NEAR lines at least from the DLIs round it and DLI_GAP
    # above a colour DLI or the top's last row (the sky's end: level 1's)
    def zone_start(i):
        kind, r = lines[i][0], lines[i][1]
        if kind != 2:
            return False
        if i == 0 or lines[i - 1][0] != 2 or lines[i - 1][1] != r - 1:
            return True
        if r < L.FB_TOP:
            return r % L.TOP_ZONE == 0
        if r <= L.BAND_ZEND:
            return (r - L.FB_TOP) % FB_BAND % L.BAND_ZH == 0
        return False
    sky_off = [i for i, ln in enumerate(lines) if ln[0] == 2 and ln[1] == L.FB_TOP - 1]
    dl = [i for i, ln in enumerate(lines) if ln[2]]
    for k, i in enumerate(dl):
        if k in COLOUR_DLIS or lines[i][0] != 2 or zone_start(i):
            continue
        lo = dl[k - 1] + DLI_NEAR if k else 0
        hi = dl[k + 1] - (DLI_GAP if k + 1 in COLOUR_DLIS else DLI_NEAR) if k + 1 < len(dl) else len(lines) - 1
        best = None
        for j in range(max(lo, 0), min(hi, len(lines) - 1) + 1):
            if not zone_start(j) or any(s > j and s - j < DLI_GAP for s in sky_off):
                continue
            if best is None or abs(j - i) < abs(best - i):
                best = j
        if best is not None:
            lines[i][2] = False
            lines[best][2] = True
            dl[k] = best
    # as runs again: buffer rows' runs broken where the rows jump and before a
    # DLI (the run's DLI_FIRST), empty runs (blank, mode-8: BuildDll lists
    # them alike whatever their count; the mode-8 rows' argument is unused
    # now) after a DLI (theirs on the run's last line): DESCBUF's room
    runs = []
    for kind, a, dli in lines:
        if runs:
            r = runs[-1]
            join = r[0] & 0x3F == kind and not r[0] & 0x80 and r[1] < 255
            if kind == 2:
                join = join and a == r[2] + r[1] and not dli
            if join:
                r[1] += 1
                if dli:
                    r[0] |= 0x80
                continue
        runs.append([kind | ((DLI_FIRST if kind == 2 else 0x80) if dli else 0), 1, a])
    out = bytearray()
    for r in runs:
        out += bytes(r)
    out.append(0xFF)
    return bytes(out)


def dli_lines(d):
    """the lines a description's DLIs come on (as the line starts), and its
    line count"""
    out, line = [], 0
    for i in range(0, len(d) - 1, 3):
        if d[i] & DLI_FIRST:
            out.append(line)
        line += d[i + 1]
        if d[i] & 0x80:
            out.append(line - 1)
    return out, line


# ------------------------------------------------------------------ build
def build(out_path):
    link = K.link(verbose=False)
    # an address into the framebuffers split in two bytes can't follow them
    # (they are no longer one block): only in code that no longer runs (the
    # buffer base $2D56 adds, skipped by RowBase; the buffer copy's setup at
    # $ADC7, replaced by SysCopyBuf)
    dead = {0x2D66, 0x2D74, 0xAD97, 0xAD9F, 0xADAA, 0xADB3, 0xADBB, 0xADC6}
    live = sorted(x for x in K.FB_RELOCS if x[1] not in dead)
    if live:
        raise SystemExit("split addresses into the framebuffers: " + ", ".join(
            "scene %d $%04X -> $%04X" % (sc, loc, t) for sc, loc, t, nt in live))
    zp = link["zp"]
    sv = L.sysvars()
    res1 = link["scenes"][1]["resolver"]
    res0 = link["scenes"][0]["resolver"]
    banks = {b: Image("bank %d" % b, 0x4000 if L.V2 and b == L.V2_LO_BANK else 0x8000) for b in range(7)}
    # (V2: the art bank's images, the art and its copies, as v1 places them,
    # in a shadow the build reads (the windows', the poses' sources: their
    # results go in MARIA's ROM) and the cart doesn't hold)
    art_src = Image("the art bank's images (V2: not in the cart)", 0x8000) if L.V2 else None
    page_src = {}           # (V2: each scene page's game data as placed, before the releases)
    fixed = Image("fixed", 0xC000)

    # --- fixed bank: bank 15, sprite copies
    org, b15 = link["shared"]["bank15"]
    fixed.place(org, b15, "bank 15")
    mem = {s: D.memory(s) for s in L.SCENES}
    for lo, hi, d, scenes in L.SPRITE_COPIES:
        src = mem[scenes[0]]
        for s in scenes[1:]:
            if any(mem[s][a] != src[a] for a in range(lo, hi)):
                # a shared copy must hold every listed scene's bytes: "the
                # same where read" was only as good as the census's reading
                # (scene 4's finale frames at $16FE-$18A1 came out as scene 2's)
                raise SystemExit("sprite copy $%04X-$%04X: scene %d's bytes differ from scene %d's"
                                 % (lo, hi - 1, s, scenes[0]))
        dest = fixed if lo + d >= 0xC000 else banks[L.ART_BANK]   # (below $C000: the art bank's)
        if L.V2 and dest is not fixed:
            dest = art_src      # (V2: read only by the loads' generators, gone: FINDINGS "The ROM by scene: step 3")
        dest.place(lo + d, bytes(src[a] for a in range(lo, hi)), "sprite copy $%04X" % lo)
    for lo, hi, d, scenes in L.ART_COPIES:
        for s in scenes[1:]:
            if any(mem[s][a] != mem[scenes[0]][a] for a in range(lo, hi)):
                raise SystemExit("art-bank copy $%04X-$%04X: scene %d's bytes differ from scene %d's"
                                 % (lo, hi - 1, s, scenes[0]))
        (art_src if L.V2 else banks[L.ART_BANK]).place(lo + d, bytes(mem[scenes[0]][a] for a in range(lo, hi)),
                                                       "art-bank sprite copy $%04X" % lo)

    # --- the fighters' parts in MARIA's ROM (port/fighters7800.py; FINDINGS
    # "BankSet step 1: the fighters' parts"): pre-cut parts both ways, the
    # heads (160B) and hit stars as tall images, packed into MARIA's half once
    # the top data has its pages; their records in the art bank (room taken
    # here, written after the packing; identical parts share one)
    fart = F.Art()
    f_pre, f_tall, f_hvar = F.maria_parts(fart, {sc: D.memory(sc) for sc in range(5)}, colour=L.V2)
    artb = banks[L.ART_BANK]
    f_key, f_rat = {}, {}

    def f_reserve(name, key, size, what):
        f_key[name] = key
        if key not in f_rat:
            at = artb.find(size, 0xA000, 0xC000)
            if at is None:
                raise SystemExit("fighters: no room in the art bank for a %d-byte record" % size)
            artb.place(at, bytes(size), what)
            f_rat[key] = at

    for n, (w, sl) in sorted(f_pre.items()):
        f_reserve(n, ("pre", w, tuple(sl)), 2 + 5 * len(sl), "fighters' part record")
    f_heads = sorted(set(f_hvar.values()), key=lambda n: int(n[4:]))
    for n in f_heads:
        f_reserve(n, ("head", n), 10, "fighters' head records")
    for n in ("star_942A", "star_94E6"):
        f_reserve(n, ("tall", n), 5, "hit star record")
    if L.V2:            # (level 2's portcullis: $A0FC's bar line 44 rows, a tall image, and each
        m2 = D.memory(2)                # bottom piece one: FINDINGS "The portcullis as one image")

        def pc_img(a):
            r, w = m2[a], m2[a + 1]
            return r, w, [[(m2[a + 2 + y * w + b] >> (6 - 2 * k)) & 3 for b in range(w) for k in range(4)]
                          for y in range(r)]
        b_r, b_w, b_p = pc_img(0x60FC)
        if b_r != 1:
            raise SystemExit("level 2's portcullis: $A0FC is %d rows, not its one bar line" % b_r)
        px = {(x, y): v for y in range(44) for x, v in enumerate(b_p[0]) if v}
        f_tall["pc_bar"] = (b_w, 44, F.PAL_GAME, F.encode_box(px, 0, b_w * 4, 0, 44, "A"))
        f_reserve("pc_bar", ("tall", "pc_bar"), 5, "portcullis record")
        for k, lo in enumerate(L.PC_TIPS_LO):
            t_r, t_w, t_p = pc_img(0x6000 + lo)
            px = {(x, y): v for y in range(t_r) for x, v in enumerate(t_p[y]) if v}
            f_tall["pc_%d" % k] = (t_w, t_r, F.PAL_GAME, F.encode_box(px, 0, t_w * 4, 0, t_r, "A"))
            f_reserve("pc_%d" % k, ("tall", "pc_%d" % k), 5, "portcullis record")

    # --- per-scene pages
    xdl = shared_display_lists(xe_display_lists(), mem)
    # a scene in another's page (the vs fight in level 1's: layout7800
    # VS_REPLACEMENTS) must need nothing of its own there
    for s in L.SCENES:
        if s not in L.PAGE_SCENES:
            own = [t for t in L.PAGE_SCENES if L.SCENE_BANK[t] == L.SCENE_BANK[s]][0]
            if not set(xdl.get(s, ())) <= set(xdl.get(own, ())):
                raise SystemExit("scene %d: display lists scene %d's page lacks" % (s, own))
            if L.CARVE_SDATA.get(s) != L.CARVE_SDATA.get(own):
                raise SystemExit("scene %d: carves unlike scene %d's" % (s, own))
    for s in L.PAGE_SCENES:
        page = banks[L.SCENE_BANK[s]]
        ch = link["scenes"][s]["chunks"]
        for name in ("scode", "common", "sdata"):
            org, data = ch[name]
            page.place(org, data, name)
        if L.V2:                # (the page's game data before any release: the build's reads, l1get)
            page_src[L.SCENE_BANK[s]] = bytes(page.data)
        # the page's dead bytes given back (layout7800 PAGE_RELEASE), if no
        # scene there has an instruction, label or relocation in them
        here = [t for t in L.SCENES if L.SCENE_BANK[t] == L.SCENE_BANK[s]]
        for lo, hi in L.PAGE_RELEASE.get(s, []):
            for t in here:
                m = link["scenes"][t]["resolver"].m
                live = sorted({a for a in range(lo, hi) if a in m.insn or a in m.reloc}
                              | {a for a in m.symbols.values() if lo <= a < hi})
                if live:
                    raise SystemExit("PAGE_RELEASE $%04X-$%04X: scene %d uses $%04X" % (lo, hi - 1, t, live[0]))
            at = [new + (lo - rlo) for rn, rlo, rhi, new, where in L.REGIONS if rlo <= lo < rhi][0]
            page.release(at, hi - lo, "released $%04X-$%04X" % (lo, hi - 1))
        # (V2) the page's data no run touched (layout7800 V2_PAGE_RELEASE),
        # byte by byte where no scene there has an instruction, label or
        # relocation
        if L.V2:
            ms_ = [link["scenes"][t]["resolver"].m for t in here]
            labs_ = {v for m in ms_ for v in m.symbols.values()}
            n_rel = 0
            for lo, hi in L.V2_PAGE_RELEASE.get(s, []) + L.V2_CODE_RELEASE.get(s, []):
                at = [new + (lo - rlo) for rn, rlo, rhi, new, where in L.REGIONS if rlo <= lo < rhi][0]
                for k in range(hi - lo):
                    x = lo + k
                    if (x in labs_ or any(x in m.insn or x in m.reloc for m in ms_)
                            or not page.used[at + k - page.base]):
                        continue
                    page.release(at + k, 1, "released (V2: no run touched) $%04X" % x)
                    n_rel += 1
            print("V2: scene %d's page: %d bytes of untouched data given back" % (s, n_rel))
        carves = bytearray()
        for lo, hi, ram in L.CARVE_SDATA.get(s, []):
            # from where the range sits in the scene page (scene data or scene
            # code), in entries of at most 255 bytes
            src = lo + (0x4000 if lo >= 0x6000 else 0x7000)
            while lo < hi:
                n = min(hi - lo, 255)
                carves += bytes([src & 0xFF, src >> 8, ram & 0xFF, ram >> 8, n])
                lo, src, ram = lo + n, src + n, ram + n
        page.place(SP["SP_NCARVE"], bytes([len(carves)]), "carve count")
        if carves:
            page.place(SP["SP_CARVE"], carves, "carves")
        entries, desc = [], bytearray()
        for at in sorted(xdl.get(s, ())):
            d, buf, modef, m8 = describe(mem[s], at)
            if not os.environ.get("NO_DLI_SPACE"):     # (for comparison: the game's DLI lines as they are)
                d = space_dlis(d)
            dls, line = dli_lines(d)
            last_dli = max(dls or [-1])
            ndli = len(dls)
            for band in (True, False):
                ne, nz, nb = zones(d, band)
                if os.environ.get("ZONECOUNT"): print("ZC", s, hex(at), band, ne, nz, nb, d.hex())
                if ne > 85 or nz > 25 or nb > L.BAND_N:     # a DLL in its page (L.DLL_A/B), the
                    raise SystemExit("scene %d list $%04X (title %s): %d DLL entries, %d row zones, "   # zones'
                                     "%d band zones; the pages hold 85, 25 and %d"   # lists in theirs
                                     % (s, at, "off" if band else "up", ne, nz, nb, L.BAND_N))
            if ndli != GAME_DLIS:
                raise SystemExit("scene %d list $%04X has %d DLIs; the NMI count assumes %d"
                                 % (s, at, ndli, GAME_DLIS))
            if line > VBI_LINE or last_dli > VBI_LINE - VBI_MARGIN:
                raise SystemExit("scene %d list $%04X: %d lines, last DLI on %d; the vertical blank "
                                 "stand-in is line %d" % (s, at, line, last_dli, VBI_LINE))
            if len(d) > L.DESCBUF_N:
                raise SystemExit("scene %d list $%04X: a description of %d bytes; DESCBUF holds %d"
                                 % (s, at, len(d), L.DESCBUF_N))
            addr = SP["SP_DESC"] + len(desc)
            ctrl = 0x43 if modef else 0x40
            if any(st.tiles and st.sid in LS.SETS_ON and s in st.scenes and at in st.lists for st in LS.SETS):
                ctrl |= 0x10                  # (a tiles set's play lists: two-byte characters)
            entries.append((at, 0 if buf == "A" else 1, ctrl, addr, 1 if m8 else 0))
            desc += d
        if len(entries) > 8:
            raise SystemExit("scene %d: %d display lists, tables hold 8" % (s, len(entries)))
        page.place(SP["SP_NDL"], bytes([len(entries)]), "DL count")
        for i, (at, buf, ctrl, addr, m8) in enumerate(entries):
            page.place(SP["DLT_LO"] + i, bytes([at & 0xFF]), "DLT")
            page.place(SP["DLT_HI"] + i, bytes([at >> 8]), "DLT")
            page.place(SP["DLT_BUF"] + i, bytes([buf]), "DLT")
            page.place(SP["DLT_CTRL"] + i, bytes([ctrl]), "DLT")
            page.place(SP["DLT_DLO"] + i, bytes([addr & 0xFF]), "DLT")
            page.place(SP["DLT_DHI"] + i, bytes([addr >> 8]), "DLT")
            page.place(SP["DLT_M8"] + i, bytes([m8]), "DLT")
        # the scene's page map: which of pages $A0-$BF are art-bank copies
        pmap = bytearray(32)
        for lo, hi, d, scenes in L.ART_COPIES + [c for c in L.SPRITE_COPIES if c[0] + c[2] < 0xC000]:
            if s in scenes:
                for p in range((lo + d) >> 8, ((hi - 1 + d) >> 8) + 1):
                    if not 0xA0 <= p < 0xC0:
                        raise SystemExit("art-bank copy $%04X: page $%02X is outside the page map" % (lo, p))
                    for sc in L.SCENES:
                        if L.SCENE_BANK[sc] == L.SCENE_BANK[s] and p in L.OWN_SPRITE_PAGES[sc]:
                            raise SystemExit("art-bank copy $%04X: page $%02X holds scene %d's own sprites"
                                             % (lo, p, sc))
                    pmap[p - 0xA0] = 1
        page.place(L.SP_PAGEMAP, bytes(pmap), "page map")
        # bank 15's scene-dependent pointer tables, relocated for this scene
        res = link["scenes"][s]["resolver"]
        for hi_t, lo_t, n, at in L.SCENE_TABLES:
            vals = bytearray()
            for i in range(n):
                tgt = mem[s][hi_t + i] << 8 | mem[s][lo_t + i]
                nt = res.new_addr(tgt)
                if (nt & 0xFF) != (tgt & 0xFF):
                    raise SystemExit("scene %d: table $%04X entry %d: $%04X moves to $%04X, not by whole pages"
                                     % (s, hi_t, i, tgt, nt))
                vals.append(nt >> 8)
            page.place(at, bytes(vals), "table $%04X" % hi_t)
        if SP["SP_DESC"] + len(desc) > L.SP_PAGEMAP:
            raise SystemExit("scene %d: descriptions run into the scene code" % s)
        page.place(SP["SP_DESC"], bytes(desc), "descriptions")

    # --- art bank
    art = banks[L.ART_BANK]
    org, data = link["shared"]["art"]
    if L.V2:                    # (V2: the art is read only by the loads' generators: the shadow)
        art = art_src
    art.place(org, data, "art")
    for lo, hi in L.ART_RELEASE:
        for t in L.SCENES:
            m = link["scenes"][t]["resolver"].m
            live = sorted(a for a in range(lo, hi) if a in m.insn or a in m.reloc)
            if live:
                raise SystemExit("ART_RELEASE $%04X-$%04X: scene %d uses $%04X" % (lo, hi - 1, t, live[0]))
        if not (org <= lo and hi <= org + len(data)):
            raise SystemExit("ART_RELEASE $%04X-$%04X: not in the art" % (lo, hi - 1))
        art.release(lo, hi - lo, "released $%04X-$%04X" % (lo, hi - 1))
    org1, e1 = link["shared"]["engine1"]
    fixed.place(org1, e1, "engine part 1 (read-only)")
    # engine part 2's modules: the fixed bank's placed, cart RAM's one image
    # (end to end in RAM: LoadScene copies it in one go)
    e2, e2_at = bytearray(), None
    for nm, lo_e, hi_e, new_e, where_e in sorted((r for r in L.REGIONS if r[0].startswith("engine2")),
                                                 key=lambda r: r[3]):
        org_e, b_e = link["shared"][nm]
        if where_e == "fixed":
            fixed.place(org_e, b_e, "engine part 2, $%04X (read-only)" % lo_e)
        else:
            if e2_at is not None and new_e != e2_at + len(e2):
                raise SystemExit("engine part 2's cart-RAM modules aren't end to end ($%04X)" % new_e)
            e2_at = new_e if e2_at is None else e2_at
            e2 += b_e
    imgb = banks[L.IMG_BANK]                 # (the images copied at loads)
    if e2:
        if L.V2:                             # (V2: wherever bank 6 has room)
            IMG["IMG_ENGINE2"] = imgb.find(len(e2), 0x8000, 0xC000)
        imgb.place(IMG["IMG_ENGINE2"], bytes(e2), "engine image 2")
    # the fixed bank's dead padding given back (layout7800 FIXED_RELEASE), if
    # no scene has an instruction, label or relocation in it, and it lies in
    # the fixed bank in one piece
    res1r = link["scenes"][1]["resolver"]
    if os.environ.get("RELCHECK"):
        for lo, hi in L.FIXED_RELEASE:
            print("RELCHECK $%04X-$%04X: plain $%04X, resolver $%04X-$%04X" % (
                lo, hi - 1, lo + 0x2000 if 0xA000 <= lo < 0xC000 else 0, res1r.new_addr(lo), res1r.new_addr(hi - 1)))
    for lo, hi in L.FIXED_RELEASE:
        for t in L.SCENES:
            m = link["scenes"][t]["resolver"].m
            # (a sprite copy's source: its copy is the home, every reference
            # resolves there)
            copied = {a for clo, chi, d, scs in L.SPRITE_COPIES if t in scs for a in range(clo, chi)}
            live = sorted(({a for a in range(lo, hi) if a in m.insn or a in m.reloc}
                           | {a for a in m.symbols.values() if lo <= a < hi}) - copied)
            if live:
                raise SystemExit("FIXED_RELEASE $%04X-$%04X: scene %d uses $%04X" % (lo, hi - 1, t, live[0]))
        # (by the region's own placing: the resolver sends a copied range's
        # address to its copy)
        reg = [new + (lo - rlo) for rn, rlo, rhi, new, where in L.REGIONS if rlo <= lo < rhi and where == "fixed"]
        at = reg[0] if reg else res1r.new_addr(lo)
        if 0xA000 <= lo < 0xC000:       # (bank 15, reassembled: from the last instruction before)
            m1 = link["scenes"][1]["resolver"].m
            gone = [(k, v[0]) for k, v in L.replacements(1).items()]     # (not in the cart: a replaced range's)
            last = max(a for a in m1.insn if a < lo and not any(k <= a < e for k, e in gone))
            end = last + oplen(D.memory(1)[last])                       # (past it, in the original)
            at = res1r.new_addr(last) + (end - last) + (lo - end) - sum(e - k for k, e in gone if end <= k and e <= lo)
        if (not reg and res1r.new_addr(hi - 1) != at + hi - 1 - lo) or not 0xC000 <= at:
            raise SystemExit("FIXED_RELEASE $%04X-$%04X: not one run in the fixed bank" % (lo, hi - 1))
        # (the bytes there must be the original's padding: bank 15 is
        # reassembled, and a padding byte, with no instruction, resolves by the
        # region's plain offset, wrong past any routine that changed length.
        # $B2F0's did: the gate death's routine at $D2E7 was overwritten, a hang)
        got, want = bytes(fixed.data[at - fixed.base:at - fixed.base + hi - lo]), bytes(D.memory(1)[a] for a in range(lo, hi))
        if got != want:
            raise SystemExit("FIXED_RELEASE $%04X-$%04X: $%04X holds other bytes than the original's (%s), not its padding"
                             % (lo, hi - 1, at, got[:8].hex()))
        fixed.release(at, hi - lo, "released $%04X-$%04X" % (lo, hi - 1))
    # the blitters' replacements' NOP tails (inside the replaced ranges, so
    # the model's instructions there are the game's old ones: not checked
    # as FIXED_RELEASE's are)
    reps1 = L.replacements(1)
    for lo, hi in L.ENGINE2_PAD_RELEASE:
        if not any(k <= lo and hi <= v[0] for k, v in reps1.items()):
            raise SystemExit("ENGINE2_PAD_RELEASE $%04X-$%04X: not inside a replacement" % (lo, hi - 1))
        at = [new + (lo - rlo) for rn, rlo, rhi, new, where in L.REGIONS if rlo <= lo < rhi][0]
        fixed.release(at, hi - lo, "padding $%04X-$%04X" % (lo, hi - 1))
    # and the replacements' dead remains (layout7800 DEAD_RELEASE: unreachable,
    # and no run reads them), each inside one replacement too
    for lo, hi in L.DEAD_RELEASE:
        if not any(k <= lo and hi <= v[0] for k, v in reps1.items()):
            raise SystemExit("DEAD_RELEASE $%04X-$%04X: not inside a replacement" % (lo, hi - 1))
        at = [new + (lo - rlo) for rn, rlo, rhi, new, where in L.REGIONS if rlo <= lo < rhi and where == "fixed"][0]
        fixed.release(at, hi - lo, "dead $%04X-$%04X" % (lo, hi - 1))
    # (V2) the blitters' dead code given back (layout7800 V2_DEAD_RELEASE):
    # each range wholly placed, released byte by byte as it lies
    if L.V2:
        for lo, hi in L.V2_DEAD_RELEASE:
            n_ = 0
            for x in range(lo, hi):
                if fixed.used[x - fixed.base]:
                    fixed.release(x, 1, "dead (V2) $%04X" % x)
                    n_ += 1
            if n_ == 0:
                raise SystemExit("V2_DEAD_RELEASE $%04X-$%04X: nothing placed there" % (lo, hi - 1))
    # the small-sprite block's image, plus the 14 bytes after it: the story
    # font's hyphen glyph (character $7E, 12x1) sits at $06E8-$06F5, where the
    # common bank begins, and the renderer reaches it as $0480 + offset, so on
    # the 7800 it must follow the block in RAM too ($1DE8-$1DF5; the bytes stay
    # in the common bank as well, where the font table at $06F4 is read from).
    # It is the same in every scene. (Without it the hyphen in "self-concern"
    # read a zero-height header, and the blit ran 256 rows through the engine:
    # FINDINGS "Story crash".)
    tail = bytes(D.memory(0).get(a, 0) for a in range(SPRITE_TAIL[0], SPRITE_TAIL[1]))
    for s in L.SCENES:
        if bytes(D.memory(s).get(a, 0) for a in range(*SPRITE_TAIL)) != tail:
            raise SystemExit("the sprite-block tail $%04X-$%04X differs in scene %d" % (SPRITE_TAIL + (s,)))
    if L.V2:
        IMG["IMG_SPRITES"] = imgb.find(len(link["shared"]["sprites"][1] + tail), 0x8000, 0xC000)
    imgb.place(IMG["IMG_SPRITES"], link["shared"]["sprites"][1] + tail, "small-sprite image")

    # --- system code
    eq = dict(HW)
    eq.update(sv)
    eq.update(SP)
    eq.update(IMG)
    # the vs fight in level 1's page (layout7800 VS_REPLACEMENTS); its sound's
    # frame-wait counters are $0AF9/$0AFA where level 1's are $0AFC/$0AFD
    # (SysFwLo, SysFwHi choose)
    eq.update({"VS_SCENE": L.VS_SCENE, "G_ZFF": zp[0xFF],
               "G_L0AFC": res1.new_addr(0x0AFC), "G_L0AFD": res1.new_addr(0x0AFD),
               "G_L0AF9": res1.new_addr(0x0AF9), "G_L0AFA": res1.new_addr(0x0AFA),
               "CARVE_E2_AT": L.CARVE_ENGINE2[0][2], "CARVE_E2_N": L.CARVE_ENGINE2[-1][2] + L.CARVE_ENGINE2[-1][1]
                                                     - L.CARVE_ENGINE2[-1][0] - L.CARVE_ENGINE2[0][2]})
    if any(c[2] != L.CARVE_ENGINE2[0][2] + sum(d[1] - d[0] for d in L.CARVE_ENGINE2[:i])
           for i, c in enumerate(L.CARVE_ENGINE2)):
        raise SystemExit("CARVE_ENGINE2: LoadScene zeroes one run, so its parts must be end to end")
    eq.update({
        "ZP_P1": zp[0x00], "ZP_P2": zp[0x02], "G_ZD0": zp[0xD0], "G_Z04": zp[0x04], "G_Z1C": zp[0x1C],
        "G_ENTRY0": res0.new_addr(0x7760), "G_L1000": res1.new_addr(0x1000),
        "G_L101F": res1.new_addr(0x101F), "G_L258D": res1.new_addr(0x258D),
        "G_L2426": res1.new_addr(0x2426), "G_L0F17": res1.new_addr(0x0F17),
        "G_L2800": res1.new_addr(0x2800),               # the blitters' module (RowBase)
        "E2_BPAGES": (0x2C00 - 0x2800) >> 8,
        "G_L2D78": res1.new_addr(0x2D78), "G_L2CCD": res1.new_addr(0x2CCD), "G_L2D03": res1.new_addr(0x2D03), "G_L2DA1": res1.new_addr(0x2DA1), "G_L2DA2": res1.new_addr(0x2DA2),
        "G_Z06": zp[0x06], "G_Z07": zp[0x07], "G_Z0D": zp[0x0D], "G_Z14": zp[0x14], "G_Z15": zp[0x15],
        "G_ZB6": zp[0xB6], "G_ZB7": zp[0xB7], "ST_ROW": L.FB_ROWS,        # the status bar's cache
        "G_Z3E": zp[0x3E], "G_ZB0": zp[0xB0],      # (the guard's type and strength: his colours)
        "G_ZE3": zp[0xE3], "G_ZE5": zp[0xE5],      # (the fighters' columns: ErDec, the box erase's)
        "G_ZC4": zp[0xC4], "G_ZDB": zp[0xDB], "G_ZDC": zp[0xDC], "G_Z46": zp[0x46], "G_Z47": zp[0x47],  # (Buttons)
        "MP1C1": 0x25, "MP1C2": 0x26, "MP1C3": 0x27, "MP5C1": 0x35, "MP5C2": 0x36, "MP5C3": 0x37,
        "FUJI_C1": FJ.FUJI_PAL[0], "FUJI_C2": FJ.FUJI_PAL[1], "FUJI_C3": FJ.FUJI_PAL[2],
        "TBC_X0": 0x0140, "TBC_X1": 0x015C, "TBC_TAG": 0x0178,   # (V2: the top boxes' cache)
        "MP6C1": 0x39, "MP6C2": 0x3A, "MP6C3": 0x3B, "MP7C1": 0x3D, "MP7C2": 0x3E, "MP7C3": 0x3F,
        "G_Z05": zp[0x05], "G_Z0E": zp[0x0E], "G_Z0F": zp[0x0F], "G_Z10": zp[0x10],   # the column routine
        "G_Z16": zp[0x16], "G_Z1E": zp[0x1E], "G_Z1F": zp[0x1F], "G_Z52": zp[0x52],
        "G_Z4C": zp[0x4C], "G_Z30": zp[0x30], "RAILS_SRC": 0xAA11,    # (level 1's worlds)
        "G_L284E": res1.new_addr(0x284E), "G_L280C": res1.new_addr(0x280C),
        "G_Z02": zp[0x02], "G_Z12": zp[0x12], "G_L2D3E": res1.new_addr(0x2D3E),   # the fast fill

        "RAMFILL_AT": K.RAMFILL_TABLE,
        "G_L0B27": res1.new_addr(0x0B27), "G_L0B3E": res1.new_addr(0x0B3E), "G_L0B98": res1.new_addr(0x0B98),
        "G_L0AFE": res1.new_addr(0x0AFE), "G_LB60F": res1.new_addr(0xB60F),
        "G_L0B26": res1.new_addr(0x0B26), "G_L2422": res1.new_addr(0x2422),   # the warning tune
        "FB_ROWS": L.FB_ROWS, "CLIPROW": sv["S_CLIPROW"] + 1,   # +1: blitter B starts a byte early
        "DESCBUF": L.DESCBUF, "ART_BANK": L.ART_BANK, "TOP_BANK": L.TOP_BANK, "IMG_BANK": L.IMG_BANK, "LOADER_BANK": L.LOADER_BANK, "ENDING_BANK": L.ENDING_BANK, "V2_LO_BANK": L.V2_LO_BANK, "DLL_A": L.DLL_A, "DLL_B": L.DLL_B, "DLL_LINES": DLL_LINES, "VBI_LINE": VBI_LINE, "VBI_NMI": GAME_DLIS + 1,
        "VBI_SPIN": VBI_SPIN,
        "FB_TOP": L.FB_TOP, "TOP_ZONE": L.TOP_ZONE,
        "FB_PTOP": FB_PTOP, "FB_PBOT": FB_PBOT, "FB_BAND": FB_BAND, "BAND_ZH": L.BAND_ZH, "BAND_ZEND": L.BAND_ZEND, 
        "BAND_A": L.BAND_A, "BAND_B": L.BAND_B, "BAND_AEND": L.BAND_AEND, "BAND_BEND": L.BAND_BEND, "DL_W": DL_W,
        "BANDX_A": L.BANDX_A, "BANDX_AEND": L.BANDX_AEND, "BANDX_B": L.BANDX_B, "BANDX_BEND": L.BANDX_BEND,
        "S_BX": L.S_BX, "S_NOFILL": L.S_NOFILL, "S_ERS": L.S_ERS, "FT_DRW": L.FT_DRW,
        "G_LA78F": res1.new_addr(0xA78F), "G_LA797": res1.new_addr(0xA797),
        "DLS_A": L.DLS_A, "DLS_B": L.DLS_B, "SMALLDL_AT": L.SMALLDL_AT,
        "G_Z03": zp[0x03], "G_ZE0": zp[0xE0], "G_ZE2": zp[0xE2],
        # the blitters in ROM (;;; FAR (BlRom))
        "G_Z0A": zp[0x0A], "G_Z0B": zp[0x0B], "G_Z19": zp[0x19], "G_L0AF6": res1.new_addr(0x0AF6), "G_L0AF9": res1.new_addr(0x0AF9), "G_L0AFA": res1.new_addr(0x0AFA), "G_L0AFC": res1.new_addr(0x0AFC), "G_L0AFD": res1.new_addr(0x0AFD), "G_L0F17": res1.new_addr(0x0F17), "G_L1000": res1.new_addr(0x1000), "G_L101F": res1.new_addr(0x101F), "G_L2426": res1.new_addr(0x2426), "G_L258D": res1.new_addr(0x258D), "G_L2800": res1.new_addr(0x2800), "G_L280C": res1.new_addr(0x280C), "G_L284E": res1.new_addr(0x284E), "G_L292E": res1.new_addr(0x292E), "G_L298D": res1.new_addr(0x298D), "G_L2981": res1.new_addr(0x2981), "G_L2948": res1.new_addr(0x2948), "G_L2B40": res1.new_addr(0x2B40), "G_L2985": res1.new_addr(0x2985), "G_L2BC0": res1.new_addr(0x2BC0), "G_Z1D": zp[0x1D], "G_L2991": res1.new_addr(0x2991), "G_L2B19": res1.new_addr(0x2B19), "G_L2CCD": res1.new_addr(0x2CCD), "G_L2D03": res1.new_addr(0x2D03), "G_L2D3E": res1.new_addr(0x2D3E), "G_L2DA1": res1.new_addr(0x2DA1), "G_L2DA4": res1.new_addr(0x2DA4), "G_LA78F": res1.new_addr(0xA78F), "G_LA797": res1.new_addr(0xA797),
        # the fighters as objects (FINDINGS "The fighters as objects: step 3")
        "G_Z20": zp[0x20], "G_Z21": zp[0x21], "G_Z22": zp[0x22], "G_Z50": zp[0x50], "G_Z2C": zp[0x2C],
        "G_Z3E": zp[0x3E], "G_Z36": zp[0x36], "G_Z4D": zp[0x4D],
        "G_LA054": res1.new_addr(0xA054), "G_LA2BE": res1.new_addr(0xA2BE), "G_L1148": res1.new_addr(0x1148),
        **{"G_L%04X" % a: res1.new_addr(a) for a in (0xA150, 0xA17A, 0xA1A4, 0xA1DA, 0xA200, 0xA226, 0xA24C,
                                                     0xA272, 0xA298, 0xA975, 0xA980, 0x0878)},
        "FT_P0": L.FT_P0, "FT_PTOP": L.FT_PTOP, "FT_PAL": L.FT_PAL, "FT_FON": L.FT_FON, "FO_BOFF": L.FO_BOFF,
        "FT_PALR": 0x21 + 4 * L.FT_PAL, "FT_PALB": L.FT_PAL << 5, "TOP_PAL2B": L.TOP_PAL2 << 5, "FT_MIR": 0xF500, "FT_NCELL": len(F.ZONES),
        "FS_I": L.FS_I, "FS_BOFF": L.FS_BOFF, "FC_START": L.FC_START, "FC_N": L.FC_N,
        "FC_CUR": L.FC_CUR,
        "FT_COLS": L.FT_COLS, "AK_COLS": L.AK_COLS, "FT_BLKCOL": L.FT_BLKCOL, "FT_BLKW": L.FT_BLKW, "FG_N": L.FG_N, "G_Z1E": zp[0x1E], "G_Z09": zp[0x09],
        "G_L284E": res1.new_addr(0x284E), "G_L2B8B": res1.new_addr(0x2B8B),
        **L.FT_TABLES,
        "J_VSSETUP": K.sys_symbols()["ScVsSetup"], "SCID_PAGE": res1.new_addr(0x7FE7), "L1_BANK": L.SCENE_BANK[1],
        "J_L1GEN": K.sys_symbols()["ScL1Gen"],
        "J_L1FETCH": K.sys_symbols()["SysL1Fetch"],
        "J_L1COL": K.sys_symbols()["SysL1Col"], "G_Z08": zp[0x08], "G_L2DA4": res1.new_addr(0x2DA4),
        "J_TOPCOLUMN": K.sys_symbols()["SysTopColumn"], "J_FGCOL": K.sys_symbols()["SysFgCol"],
        "J_ROWNEXT": K.sys_symbols()["SysRowNext"], "J_ROWADDR": K.sys_symbols()["SysRowAddr"],   # for the pieces assembled apart
        "SP_PAGEMAP": L.SP_PAGEMAP, "RAM_SPRITES": 0x1B80, "LEN_SPRITES": SPRITE_TAIL[1] - 0x0480,
        "RAM_ENGINE2": min([r[3] for r in L.REGIONS if r[0].startswith("engine2") and r[4] == "cram"] or [0]),
        "LEN_ENGINE2": sum(r[2] - r[1] for r in L.REGIONS if r[0].startswith("engine2") and r[4] == "cram"),
        "SWAPBUF": L.CARVE_COMMON[0][2],
        # the story as letter objects
        "STORY_G": L.STORY_G, "STORY_GTAB": L.STORY_GTAB, "STORY_TPL": L.STORY_TPL,
        # the top rows' objects (FINDINGS "The top rows as objects")
        "TOP_PBASE": L.TOP_PBASE, "TOP_DLO": L.TOP_DLO, "TOP_DEND": L.TOP_DEND,
        "TOPDL_A": L.TOPDL_A, "TOPDL_B": L.TOPDL_B, "TOPDL_N": L.TOPDL_N,
        "TOPDL_AEND": L.TOPDL_AEND, "TOPDL_BEND": L.TOPDL_BEND, "TOPDL_SIZE": L.TOPDL_SIZE,
        "TOPDL_LAST": L.TOPDL_LAST,
        "G_Z09": zp[0x09],
        # the game's colour sets ($1125): the scheme, its pointers, the fade
        "G_L0F0C": res1.new_addr(0x0F0C), "G_L1197": res1.new_addr(0x1197),
        "G_L0AF6": res1.new_addr(0x0AF6),               # the game's flip wait (negative: waiting)
        "G_L119D": res1.new_addr(0x119D), "G_L0F12": res1.new_addr(0x0F12),
        "G_L0F14": res1.new_addr(0x0F14),               # the game's DLI count in the frame
        "TOP_PALR": 0x21 + 4 * L.TOP_PAL1,             # the converted pieces' palette's colour 1
        "TOP_PAL2R": 0x21 + 4 * L.TOP_PAL2,            # the opaque pieces' second palette's
        "TOPLI": L.TOPLI, "TOPLX": L.TOPLX, "TOPLK0": L.TOPLK0, "TOPLK1": L.TOPLK1,
        "TOPLN": L.TOPLN, "TOPLBG": L.TOPLBG, "TOPL_MAX": L.TOPL_MAX, "S_TPB": L.S_TPB, **L.TSVARS,
        "TS_CHB": L.TS_CHB, "TS_DLIS": L.TS_DLIS, "TS_CHTV": L.TS_CHTV, "TS_CHTP": L.TS_CHTP,
        "TS_DLA": L.TS_DLA, "TS_DLB": L.TS_DLB, "TS_DLAEND": L.TS_DLAEND, "TS_DLBEND": L.TS_DLBEND,
        "TOPLD": L.TOPLD, "TOPDL_ARG": L.TOPDL_ARG, "TOPZ_ARG": L.TOPZ_ARG, "TOPZ_H": L.TOPZ_H,
        "TP_EK": L.TP_EK, "TP_PASS": L.TP_PASS, "TP_T0": L.TP_T0, "TP_T1": L.TP_T1, "TP_T2": L.TP_T2,
        "TOPBLACKDL": L.TOPBLACKDL, "TOP_BLACKW": (L.TOP_PAL1 << 5) | (-20 & 0x1F),
        "TOP_MIRROR": res0.new_addr(0x2BC0),            # the mirrored blitter's byte table
        "TOP_RETA": res0.new_addr(0x284E) + 2,          # a blit's JSR $29D8 return: normal
        "TOP_RETMR": res0.new_addr(0x2B8B) + 2,         # and mirrored, right-aligned
        "TOP_RETM": res0.new_addr(0x2B82) + 2,          # and mirrored, its column the left byte's
        "BL_RETAR": res0.new_addr(0x29C2) + 2,          # and normal, its column the right byte's
        "G3_L6980": link["scenes"][3]["resolver"].new_addr(0x6980),   # level 3's hawk drawing
        "AK_MAX": L.AK_MAX,
        "TOP_RETRECT": res0.new_addr(0x2CD2) + 2,       # the rectangle fill's JSR $2D46 return
        "STORY_PATA": L.STORY_PATA, "STORY_PATB": L.STORY_PATB, "STORY_PATN": L.STORY_PATN, "STORY_FIRST": L.STORY_FIRST,
        "STORY_N": L.STORY_N, "STORY_PITCH": L.STORY_PITCH, "STORY_ROW0": L.STORY_ROW0,
        "STORY_TOP": L.STORY_TOP, "STORY_BOT": L.STORY_BOT, "STORY_PACE": L.STORY_PACE,
        "STORY_L0": L.STORY_ROW0 // L.STORY_PITCH,
        "DL_PAL": PAL << 5,
        "G_STORYLO": res0.new_addr(0x7BCC), "G_STORYHI": res0.new_addr(0x7BE6),
        "G_GLYLO": res0.new_addr(0x06F4), "G_GLYHI": res0.new_addr(0x0714),
        "G_ADVC": res0.new_addr(0x0734), "G_ADVS": res0.new_addr(0x0754),
        "G_GLYBASE": res0.new_addr(0x0480),
        "STATUS_DLA": L.STATUS_DLA, "STATUS_DLB": L.STATUS_DLB, "STATUS_PG": L.STATUS_DLA & 0xFF00,
        # the status strips: the full bars in the status rows' place (buffer
        # A's for the player's, B's for the foe's), a row a page from row 146
        "ST_PLO": L.ST_PLO, "ST_FLO": L.ST_FLO, "ST_HI": L.ST_HI, "ST_ROWS": ROWS - L.FB_ROWS,
        "STORY_PLO": L.STORY_PLO, "STORY_PHI": L.STORY_PHI, "END_N": L.END_N, "END_BOT": L.END_BOT,
        "G_ENDLO": link["scenes"][4]["resolver"].new_addr(0x6318),
        "G_ENDHI": link["scenes"][4]["resolver"].new_addr(0x6323),
    })
    # zero-page tables: XEGS $00-$7F by where they live now
    za, zb = [], []
    for z in range(0x80):
        t = zp[z]
        (za if t < 0x100 else zb).append((t, z))
    ccarve = bytearray()
    for lo, hi, ram in L.CARVE_COMMON:
        src = lo - 0x06E8 + 0x96E8
        ccarve += bytes([src & 0xFF, src >> 8, ram & 0xFF, ram >> 8, hi - lo])
    if len({eq[k] & 0xFF for k in ("TOP_RETA", "TOP_RETM", "TOP_RETMR")}) != 3:
        raise SystemExit("TopCapture tells the blits apart by their returns' low bytes: two are the same")
    pg = {k: eq[k] >> 8 for k in ("TOP_RETA", "BL_RETAR", "TOP_RETM", "TOP_RETMR")}
    if len({pg["TOP_RETA"], pg["BL_RETAR"], pg["TOP_RETM"]}) != 3 or pg["TOP_RETM"] != pg["TOP_RETMR"]:
        raise SystemExit("BlitBankL1 tells the blits apart by their returns' pages: %s" % pg)
    eq.update({"N_ZA": len(za), "N_ZB": len(zb), "N_CCARVE": len(L.CARVE_COMMON),
               "CCARVE_BYTES": len(ccarve)})
    src = v_filter(open(os.path.join(HERE, "sys7800.asm")).read()).replace("CPX #N_CCARVE*5", "CPX #CCARVE_BYTES")

    def by(vals):
        return ["    .byte " + ",".join("$%02X" % v if isinstance(v, int) else v for v in vals[i:i + 16])
                for i in range(0, len(vals), 16)] or ["    .byte $00"]
    # the zero-page tables live in every scene page (the swap and clear run
    # with it selected), at $9300
    zpt = bytes([t for t, z in za] + [z for t, z in za] + [t - 0x1800 for t, z in zb] + [z for t, z in zb])
    eq.update({"ZPT_A": 0x9300, "ZPT_AX": 0x9300 + len(za), "ZPT_B": 0x9300 + 2 * len(za),
               "ZPT_BX": 0x9300 + 2 * len(za) + len(zb)})
    for s in L.PAGE_SCENES:
        banks[L.SCENE_BANK[s]].place(0x9300, zpt, "zero-page tables")
    # the common-bank carve list and the scene-to-bank table: read by the
    # loaders, which always run with a scene page in; in every scene page
    sbt = bytes([L.SCENE_BANK.get(s, L.SCENE_BANK[0]) for s in range(7)])
    at = 0x9300 + len(zpt)
    eq.update({"CCARVE": at, "SCENEBANK_TAB": at + len(ccarve)})
    for s in L.PAGE_SCENES:
        banks[L.SCENE_BANK[s]].place(at, bytes(ccarve) + sbt, "loader tables")
    # the empty DL and the blank DLL: display lists must be in RAM, so these
    # static ones are copied at boot from an image in the fixed bank to
    # console RAM SMALLDL_AT (sys7800 Reset). (The three mode-8 rows' lists
    # went with the rows' widening: they show the background now)
    small = bytes([0, 0])
    eq.update({"DL_EMPTY": L.SMALLDL_AT, "BLANK_DLL": L.SMALLDL_AT + len(small)})
    # the blank list: the six dummy DLIs and VBI_LINE as one-line zones
    # (MARIA raises a zone's DLI as the zone starts, so a flagged zone must be
    # exactly the flagged line, as in the game lists), the lines between them in
    # unflagged zones of up to 16 lines; so it has the game lists' seven NMIs,
    # on the same lines
    flagged = set(BLANK_DLIS + (VBI_LINE,))
    dll, line = bytearray(), 0
    while line < DLL_LINES:
        if line in flagged:
            h, dli = 1, 0x80
        else:
            nxt = min([e for e in flagged if e > line] or [DLL_LINES])
            h, dli = min(16, nxt - line), 0
        dll += bytes([dli | (h - 1), eq["DL_EMPTY"] >> 8, eq["DL_EMPTY"] & 0xFF])
        line += h
    image = small + bytes(dll)
    # the NMI's first instructions (sys7800 Nmi): PHA, JMP NmiGo; or (TsFirst
    # puts LDA abs at +1) the title's and story's CHBASE and DLIs of ours
    # (NmiGo's address set once assembled, at +2 and +18; S_NMICOUNT at +21)
    st = L.SMALLDL_AT + len(image)
    eq["NMI_STUB"] = st
    nmi_stub_off = len(image)
    image += bytes([0x48, 0x4C, 0x00, 0x00,                        # PHA; JMP NmiGo (or LDA TS_CHTV+n)
                    0x85, 0x34,                                    # STA M_CHBASE
                    0xEE, (st + 2) & 0xFF, (st + 2) >> 8,          # INC (the first operand)
                    0xEE, (st + 13) & 0xFF, (st + 13) >> 8,        # INC (the second)
                    0xAD, 0x00, L.TS_CHTP >> 8,                    # LDA TS_CHTP+n+1
                    0xD0, 0x03,                                    # BNE ours
                    0x4C, 0x00, 0x00,                              # JMP NmiGo
                    0xEE, 0x00, 0x00,                              # ours: INC S_NMICOUNT
                    0x68, 0x40])                                   # PLA, RTI
    if L.SMALLDL_AT + len(image) > 0x2800:
        raise SystemExit("the static display lists run past console RAM ($%04X + %d)" % (L.SMALLDL_AT, len(image)))
    eq["LEN_SMALLDL"] = len(image)       # the image: in the spare bank (IMG_SMALLDL)
    small_image = image
    # the POKEY-to-TIA sound tables (port/sndconv.py, SND_OFFSET), in the top
    # bank with TiaSound (above the images copied at loads)
    import sndconv
    for name, blob in sndconv.tables(SND_OFFSET).items():
        if name.startswith("="):
            eq[name[1:]] = blob
            continue
        where = banks[L.TOP_BANK].find(len(blob), 0xA000, 0xC000)
        if where is None:
            raise SystemExit("bank %d: no room for %s (%d bytes)" % (L.TOP_BANK, name, len(blob)))
        banks[L.TOP_BANK].place(where, blob, name)
        eq[name] = where
    # (the row lists were in ROM; now each zone's is built in RAM, and the
    # static ones are copied there at boot from this image, in the bank the
    # vs fight's page left free: L.SPARE_BANK)
    if not L.V2:        # (V2: in the fixed bank, with the far pieces)
        banks[L.SPARE_BANK].place(0x8000, small_image, "static display lists' image")
        eq["IMG_SMALLDL"] = 0x8000
    eq["SPARE_BANK"] = L.SPARE_BANK
    tables = []
    # the status bar's arrow patterns (layout7800.py, from the game's two
    # arrow images, which its code in their place no longer holds): check
    # the images are the game's
    m1 = D.memory(1)
    for img, want in L.ARROW_IMG.items():
        if [m1[img + i] for i in range(len(want))] != want:
            raise SystemExit("the status arrow image at $%04X is not layout7800.ARROW_IMG's" % img)
    # the title's objects (FINDINGS "The title as objects"): the logo's 8 from
    # the game's table ($795A-$797F: source, column, top line, shift) and the
    # two copyright lines from the immediates of $7918 and $2179 (their
    # $03/$04/$05/$06/$10); x = 4 x column + shift / 2, row = top line - 35
    m0 = D.memory(0)

    def imm_blit(at):
        """the source, column, line and shift a routine sets before its blit
        (LDA #n / STA zp pairs from `at`)"""
        vals, pc = {}, at
        while len(vals) < 5:
            if m0[pc] == 0xA9 and m0[pc + 2] == 0x85:
                vals[m0[pc + 3]] = m0[pc + 1]
                pc += 4
            else:
                pc += 1
        return vals[0x04] << 8 | vals[0x03], vals[0x05], vals[0x06], vals[0x10]
    tobj = []
    for x in range(8):
        isrc = m0[0x7962 + x] << 8 | m0[0x795A + x]
        tobj.append((isrc, m0[0x796A + x], m0[0x7972 + x], m0[0x797A + x], 0))
    for at in (0x7918, 0x217C):
        tobj.append(imm_blit(at) + (1,))
    rows = {0: [], 1: []}
    for isrc, col, line, shift, can in tobj:
        rows[can] += [line - 35, line - 35 + m0[isrc] - 1]
    t0, b0, t1, b1 = min(rows[0]), max(rows[0]), min(rows[1]), max(rows[1])
    plo = L.TITLE_G - max(b0 - t0, b1 - t1)
    if not (t0 < t1 and plo > 0x42 and L.TITLE_TPL > L.TITLE_G):     # (above the pages' reserved heads)
        raise SystemExit("title canvases: rows %d-%d, %d-%d, pages from $%02X" % (t0, b0, t1, b1, plo))
    # the patched lists' areas: framebuffer pages none of the objects' data use
    used = {"the title's canvases": range(plo, L.TITLE_G + 1),
            "the title's templates": range(L.TITLE_TPL, L.TITLE_TPL + 1),
            "the story's glyphs and their table": range(L.STORY_GTAB >> 8, L.STORY_G + 1),
            "the story's templates": range(L.STORY_TPL, L.STORY_TPL + (L.STORY_N + 1) // 2)}
    for name, lo in (("A", L.STORY_PATA), ("B", L.STORY_PATB)):
        pages = set(range(lo, lo + L.STORY_PATN))
        if not all(0x40 <= p <= FB_PTOP for p in pages):      # cart RAM (the story's time: the buffers idle)
            raise SystemExit("patched lists %s: pages $%02X-$%02X outside cart RAM's pages" % (name, lo, lo + L.STORY_PATN - 1))
        for what, r in used.items():
            if pages & set(r):
                raise SystemExit("patched lists %s ($%02X-$%02X) overlap %s" % (name, lo, lo + L.STORY_PATN - 1, what))
    if set(range(L.STORY_PATA, L.STORY_PATA + L.STORY_PATN)) & set(range(L.STORY_PATB, L.STORY_PATB + L.STORY_PATN)):
        raise SystemExit("the two buffers' patched lists overlap")
    res0t = link["scenes"][0]["resolver"]
    tp = [res0t.new_addr(isrc) for isrc, col, line, shift, can in tobj]
    # (in the top bank, with TitleLayout: FINDINGS "The title and story code in bank 5")
    title_tab = ["", ";;; FARART (TITLE_TAB)"]
    title_tab += ["TITLE_SLO:"] + by([a & 0xFF for a in tp]) + ["TITLE_SHI:"] + by([a >> 8 for a in tp])
    title_tab += ["TITLE_X:"] + by([4 * col + shift // 2 for isrc, col, line, shift, can in tobj])
    title_tab += ["TITLE_ROW:"] + by([line - 35 for isrc, col, line, shift, can in tobj])
    title_tab += ["TITLE_CAN:"] + by([can for isrc, col, line, shift, can in tobj])
    eq.update({"TITLE_N": len(tobj), "TITLE_T0": t0, "TITLE_B0": b0, "TITLE_T1": t1, "TITLE_B1": b1,
               "TITLE_G": L.TITLE_G, "TITLE_PLO": plo, "TITLE_TPL0": L.TITLE_TPL * 256 + 16,
               "TITLE_TPL1": L.TITLE_TPL * 256 + 128, "TITLE_C": L.TITLE_TPL * 256 + 200,
               "TITLE_W": L.TITLE_TPL * 256 + 220})

    # each piece after a ";;; FAR" line goes in a free gap of its own:
    # assembled once to learn its size, placed, and its labels handed to the
    # main block as equates
    # the scene-page section: assembled at the scene pages' free $9420 and
    # placed in all of them; its labels reach the main block as equates
    sp_a = src.index("\n;;; SCENEPAGE")
    sp_b = src.index("\n;;; END SCENEPAGE")
    sp_text = src[sp_a:sp_b].split("\n", 2)[2].splitlines()     # past the marker line
    src = src[:sp_a] + "\n" + src[sp_b:].split("\n", 2)[2]
    # the level-1 section: only in the scene pages that call it (scenes 1
    # and 6), at a run free in both; its labels reach the scene page
    l1_a = src.index("\n;;; LEVEL1PAGE")
    l1_b = src.index("\n;;; END LEVEL1PAGE")
    l1_parts = [[ln for ln in part.splitlines() if not ln.startswith(";;;")]
                for part in src[l1_a:l1_b].split("\n", 2)[2].split("\n;;; PART")]
    l1_parts = l1_parts[:1] + [p[1:] for p in l1_parts[1:]]     # past each ";;; PART" line
    src = src[:l1_a] + "\n" + src[l1_b:].split("\n", 2)[2]
    # (V2) the level-2 section: only in level 2's scene page (FINDINGS "Level
    # 2's windows: the joints as one entry"); its labels reach the far pieces,
    # and it theirs in the far pieces' second pass
    l2_parts = []
    if "\n;;; LEVEL2PAGE" in src:
        l2_a = src.index("\n;;; LEVEL2PAGE")
        l2_b = src.index("\n;;; END LEVEL2PAGE")
        l2_parts = [[ln for ln in part.splitlines() if not ln.startswith(";;;")]
                    for part in src[l2_a:l2_b].split("\n", 2)[2].split("\n;;; PART")]
        l2_parts = l2_parts[:1] + [p[1:] for p in l2_parts[1:]]
        src = src[:l2_a] + "\n" + src[l2_b:].split("\n", 2)[2]
    # the fast fill's code: assembled at its cart-RAM address, its image in
    # the art bank, copied at load (CopyFill)
    rf_a = src.index("\n;;; RAMFILL")
    rf_b = src.index("\n;;; END RAMFILL")
    rf_text = [ln for ln in src[rf_a:rf_b].splitlines()[1:] if not ln.startswith(";;;")]
    src = src[:rf_a] + "\n" + src[rf_b:].split("\n", 2)[2]
    # the top rows' pieces (layout7800.TOP_PIECES; FINDINGS "The top rows as
    # objects"): a global table, an array a field (each its own far piece),
    # and each scene's first index and count; their rows above the cut get
    # columns in the top data, a zone's slice each
    zkeys = ["Z%d" % z for z in range(L.TOP_NZ)]
    if L.TOP_NZ != 5:
        raise SystemExit("the top rows' code reads five zones' columns (TOP_Z0-4), not %d" % L.TOP_NZ)
    top_f = {k: [] for k in ["SRCLO", "SRCHI", "ROW", "ROWS", "W", "FLAGS", "PALW"] + zkeys + ["Z4O"]}
    # the last zone (rows 60-64: 5 of the grid's 15 pages): its slices are
    # stored 0, 5 or 10 pages lower, three to a column (TOP_Z4O)
    z4_rows = L.FB_TOP - (L.TOP_NZ - 1) * L.TOP_ZONE
    z4_offs = list(range(0, L.TOP_ZONE - z4_rows + 1, z4_rows))
    top_first, top_n, top_a = [0] * 7, [0] * 7, [0] * 7
    fill_first, fill_n, fill_src = [0] * 7, [0] * 7, {}
    joint_at = {}                       # (V2: level 2's joint pieces' entries, by mirroring)
    if (L.TOP_PAL1, L.TOP_PAL2) != (2, 3):
        raise SystemExit("TopLoad tells the conversions apart by the palette's low bit: TOP_PAL1 2, TOP_PAL2 3")
    # each piece's bytes (as loaded: mirrored if it is): the first and last
    # rows with a visible pixel (transparent: colour 2 converted, else 0),
    # for TopErase's vertical rule; $FF/$00 for none
    nt_i, nt_lo, nt_hi = [], [], []
    # each set's data as TopLoad leaves it (FINDINGS "BankSet step 1: the top
    # pieces"): (scenes, 0 the first set or 1 the other) -> 15 pages of 256
    # bytes, page k holding grid row 14 - k of each zone (page TOP_PBASE - 14
    # + k at run time)
    top_data, top_sets = {}, {}
    top_groups = []         # (V2: each scene group's page and its pieces' range: FARSL)
    mirror_t = [D.memory(0)[0x2BC0 + i] for i in range(256)]     # (the mirrored blitter's byte table)
    for s0 in sorted(L.TOP_PIECES):
        if any(L.TOP_PIECES[o] is L.TOP_PIECES[s0] for o in L.TOP_PIECES if o < s0):
            continue                                 # (scenes sharing a list: done with the first)
        scenes = sorted(sc for sc in L.TOP_PIECES if L.TOP_PIECES[sc] is L.TOP_PIECES[s0])
        conv = L.TOP_CONVERT[scenes[0]]
        mem_t = D.memory(scenes[0])
        first = len(top_f["ROW"])
        res_t = link["scenes"][scenes[0]]["resolver"]
        # the scene's pieces, then its other set's (TOP_ALT: in the same
        # columns, loaded in their place when one is drawn: TopCapture)
        main, alt = L.TOP_PIECES[s0], L.TOP_ALT.get(s0, [])
        if any("fill" in p[3:] for p in alt):
            raise SystemExit("scenes %s: a fill piece in the other set (TopFillAdd reads the first)" % scenes)
        used_cols = []
        fills = [i for i, p in enumerate(L.TOP_PIECES[scenes[0]]) if "fill" in p[3:]]
        if fills and fills != list(range(fills[0], fills[0] + len(fills))):
            raise SystemExit("scenes %s: the fill pieces must be listed together (TOPSCN_FF, TOPSCN_FN)" % scenes)
        for sc in scenes:
            fill_first[sc], fill_n[sc] = first + (fills[0] if fills else 0), len(fills)
            if L.V2:            # (V2: from the group's own first index, TPG<page>: FARSL)
                fill_first[sc] = "TPG%d+%d" % (L.SCENE_BANK[sc], fills[0] if fills else 0)
        for set_i, plist in enumerate((main, alt)):
            col, z4_bins = L.TOP_DLO, []             # z4_bins: [column, width, free offsets]
            pages = [bytearray(256) for _ in range(L.TOP_ZONE)]
            top_data[(tuple(scenes), set_i)] = pages
            set_first = len(top_f["ROW"])
            for xa, top, mir, *kind in plist:
                chain_k = "chain" in kind                # a column its first piece's blit captures
                col_k = "col" in kind or chain_k         # a column: the image repeated to the cut
                one_k = "one" in kind                    # one object: a draw replaces its earlier places
                erase_k = "erase" in kind                # its blit erases (a fill over its rectangle), not kept
                fill_k = "fill" in kind                  # a fill stands for it (TOP_FILLP)
                joint_k = "joint" in kind                # (V2) level 2's joint: one entry a buffer, L2Joint
                jerase_k = "jerase" in kind              # (V2) its erase: nothing (L2Joint)
                if sum((col_k, one_k, erase_k, fill_k)) > 1:
                    raise SystemExit("top piece %s: one kind only (TOP_FLAGS)" % (xa,))
                if fill_k:
                    fp = L.TOP_FILLP[xa]
                    lab = "TOPFILL_" + xa
                    if xa not in fill_src:
                        fill_src[xa] = "\n;;; FARART (%s)\n%s:\n" % (lab, lab) + "\n".join(by(list(fp["match"]) + fp["rows"])) + "\n"
                    src7, in_art = None, False
                    rows_i, w = len(fp["rows"]), fp["w"]
                    byte_at = (lambda r, b, fp=fp: fp["rows"][r])
                else:
                    src7 = res_t.new_addr(xa)            # (XEGS address -> the scene's 7800 one)
                    in_art = 0x8000 <= xa < 0xA000       # (loaded with the art bank in)
                    rows_i, w = mem_t[xa], mem_t[xa + 1]
                    byte_at = (lambda r, b, xa=xa, w=w: mem_t[xa + 2 + r * w + b])
                    for sc in scenes[1:]:
                        m2 = D.memory(sc)
                        if [m2[xa + i] for i in range(2 + rows_i * w)] != [mem_t[xa + i] for i in range(2 + rows_i * w)]:
                            raise SystemExit("top piece $%04X: scene %d's bytes differ from scene %d's" % (xa, sc, scenes[0]))
                above = L.FB_TOP - top if col_k else min(rows_i, L.FB_TOP - top)
                # its colours as loaded: level 1's converted for the sky (colour 2
                # transparent, 0 an opaque black); "opaque" scenes' pieces drawn
                # opaque as the blitter's store does, black moved to a colour the
                # piece doesn't use (2: palette TOP_PAL1; else 1: TOP_PAL2); else
                # as drawn (colour 0 transparent). clear_c: the image's colour
                # that shows nothing
                used = {(byte_at(r % rows_i, b) >> (6 - 2 * k)) & 3 for r in range(above) for b in range(w) for k in range(4)}
                swap, pal, clear_c = None, PAL, 0
                if "fuji" in kind:                     # (V2: Mt Fuji redrawn, palette 5)
                    fj = FJ.art(rows_i, w, byte_at, top)
                    byte_at = (lambda r, b, fj=fj: fj[r][b])
                    pal = 5
                elif fill_k:
                    pal = fp["pal"]
                elif conv and "raw" not in kind:
                    if conv is True or 2 not in used:
                        swap, pal, clear_c = "02", L.TOP_PAL1, 2
                    elif 1 not in used:
                        swap, pal, clear_c = "01", L.TOP_PAL2, 1
                if col_k and rows_i > 7:
                    raise SystemExit("top column $%04X: %d rows an image, the flags hold 7" % (xa, rows_i))
                zl, z4o = [], 0
                for z in range(L.TOP_NZ):
                    r0, r1 = max(top, z * L.TOP_ZONE), min(top + above, (z + 1) * L.TOP_ZONE)
                    if r0 >= r1 or erase_k:              # (an erasing piece: no rows stored)
                        zl.append(0xFF)
                    elif z == L.TOP_NZ - 1:
                        b = next((b for b in z4_bins if b[1] >= w and b[2]), None)
                        if b is None:
                            b = [col, w, list(z4_offs)]
                            z4_bins.append(b)
                            col += w
                        zl.append(b[0])
                        z4o = b[2].pop(0)
                    else:
                        zl.append(col)
                        col += w
                # its rows' bytes as TopLoad stores them: a column's image repeated,
                # a fill's row byte across, mirrored through the byte table,
                # colours swapped 0/2 (palette TOP_PAL1) or 0/1 (TOP_PAL2)
                if not erase_k:
                    for r in range(above):
                        row = top + r
                        z, k = row // L.TOP_ZONE, row % L.TOP_ZONE
                        if zl[z] == 0xFF:
                            continue
                        pg = L.TOP_ZONE - 1 - k - (z4o if z == L.TOP_NZ - 1 else 0)
                        for b in range(w):
                            v = byte_at(r % rows_i, w - 1 - b if mir else b)
                            if mir:
                                v = mirror_t[v]
                            if swap == "02":
                                v ^= ((~v) & 0x55) << 1
                            elif swap == "01":
                                v ^= ((~v) & 0xAA) >> 1
                            pages[pg][zl[z] + b] = v & 0xFF
                run = []                                 # (an erasing piece: none; the same run shared)
                for b in range(0 if erase_k else w):
                    ob = w - 1 - b if mir else b                 # (the image's own byte)
                    vis = [top + r for r in range(above)
                           if any(((byte_at(r % rows_i, ob) >> (6 - 2 * k)) & 3) != clear_c for k in range(4))]
                    run.append((min(vis) if vis else 0xFF, max(vis) if vis else 0x00))
                pairs = list(zip(nt_lo, nt_hi))
                at = next((i for i in range(len(pairs) - len(run) + 1) if pairs[i:i + len(run)] == run), None)
                if at is None:
                    at = len(nt_lo)
                    nt_lo += [lo for lo, hi in run]
                    nt_hi += [hi for lo, hi in run]
                nt_i.append(at)
                if joint_k:
                    joint_at[mir] = len(top_f["ROW"])
                for k, v in [("SRCLO", "<" + lab if fill_k else src7 & 0xFF), ("SRCHI", ">" + lab if fill_k else src7 >> 8),
                             ("ROW", top), ("ROWS", above), ("W", w),
                             ("FLAGS", (0x80 if mir else 0) | (0x40 if swap else 0) | (0x20 if in_art else 0)
                                       | ((0x10 | rows_i) if col_k else 0) | (0x08 if one_k or chain_k else 0)
                                       | (0x04 if erase_k else 0) | (0x02 if fill_k else 0)
                                       | (0x0C if joint_k else 0) | (0x02 if jerase_k else 0)),
                             ("PALW", (pal << 5) | (-w & 0x1F))] + list(zip(zkeys, zl)) + [("Z4O", z4o)]:
                    top_f[k].append(v)
            if col > L.TOP_DEND:
                raise SystemExit("the top data for scenes %s: %d bytes a page, past %d" % (scenes, col - L.TOP_DLO, L.TOP_DEND - L.TOP_DLO))
            used_cols.append(col - L.TOP_DLO)
            top_sets[(tuple(scenes), set_i)] = (set_first, len(top_f["ROW"]), col - L.TOP_DLO)
        for sc in scenes:
            top_first[sc], top_n[sc], top_a[sc] = first, len(main), len(alt)
            if L.V2:
                top_first[sc] = "TPG%d" % L.SCENE_BANK[sc]
                eq["TPG%d" % L.SCENE_BANK[sc]] = first
        if len({L.SCENE_BANK[sc] for sc in scenes}) != 1:
            raise SystemExit("scenes %s share top pieces but not a page" % scenes)
        top_groups.append((L.SCENE_BANK[scenes[0]], first, len(top_f["ROW"])))
        print("top pieces for scenes %s: %d, %d bytes a page of top data%s" % (
            scenes, len(main), used_cols[0], "; the other set %d, %d bytes" % (len(alt), used_cols[1]) if alt else ""))
    if len(nt_lo) > 256:
        raise SystemExit("the top pieces' visible-row tables: %d entries, an index byte reaches 256" % len(nt_lo))
    # the sets into groups of 15 pages of MARIA's window block (each group's
    # 256 columns shared by sets side by side, the widest first); each set's
    # pieces' columns moved to its place; its top page per scene (TOPSCN_PB
    # the first set's, TOPSCN_PBA the other's)
    # (V2: none here: each set in its scene page's own MARIA window, placed
    # with the set's level graphics, l1reserve; top_vplace)
    groups, top_place, top_vplace = [0] * len(L.TOP_GROUPS), {}, {}
    for key, (i0, i1, width) in [] if L.V2 else sorted(top_sets.items(), key=lambda kv: -kv[1][2]):
        g = next(g for g, sc in enumerate(L.TOP_GROUPS) if key[0][0] in sc)
        if groups[g] + width > 256:
            raise SystemExit("the top data: group %d (scenes %s) past 256 columns" % (g, L.TOP_GROUPS[g]))
        top_place[key] = (g, groups[g])
        for i in range(i0, i1):
            for zk in zkeys:
                if top_f[zk][i] != 0xFF:
                    top_f[zk][i] += groups[g] - L.TOP_DLO
        groups[g] += width
    if L.TOP_MPAGE + len(groups) * L.TOP_ZONE > L.TOP_MPAGE // 0x40 * 0x40 + 0x40:
        raise SystemExit("the top data: %d groups of 15 pages, past MARIA's window" % len(groups))
    top_window = bytearray(0x4000)               # MARIA's window block ($8000-$BFFF; V2 its bank 6, $4000)
    mbase = L.TOP_MPAGE // 0x40 * 0x40           # (its first page)
    top_pb, top_pba = [0] * 7, [0] * 7
    for (sc, si), (g, off) in top_place.items():
        width = top_sets[(sc, si)][2]
        base = L.TOP_MPAGE + g * L.TOP_ZONE      # the group's first page
        for k, page in enumerate(top_data[(sc, si)]):
            a = (base + k - mbase) * 256 + off
            top_window[a:a + width] = page[L.TOP_DLO:L.TOP_DLO + width]
        for s in sc:
            (top_pba if si else top_pb)[s] = base + L.TOP_ZONE - 1
    if not L.V2:
        print("top data in MARIA's window: %d groups of 15 pages (%s)" % (len(groups), ", ".join("%d columns" % u for u in groups)))
    # the fighters' parts into the pages and columns the top data leaves in
    # MARIA's window block and into its fixed bank; read back; their records
    mspace = F.MariaSpace(bytearray(top_window) + bytearray(BANK),
                          ((0x40, 0x7F), (0xC0, 0xFF)) if L.V2 else ((0x80, 0xFF),))
    for g, used in enumerate(groups):
        for p in range(L.TOP_MPAGE + g * L.TOP_ZONE, L.TOP_MPAGE + (g + 1) * L.TOP_ZONE):
            mspace.take(p, 0, 256 if p in L.TS_PAGES and not L.V2 else used)   # (bank 0's own there)
    for p in ([] if L.V2 else L.TS_PAGES):
        if any(sc in L.TOP_GROUPS[(p - L.TOP_MPAGE) // L.TOP_ZONE] for sc in L.SCENES if L.SCENE_BANK[sc] == 0):
            raise SystemExit("TS_PAGES $%02X: a group of a scene in bank 0" % p)
    f_rec = F.pack(mspace, f_pre, f_tall)
    # the sky's switch line's 20 bytes of colour 2 in MARIA's ROM too (they
    # were in console RAM, written at each load: FINDINGS "Console RAM laid
    # out scene by scene"): a one-line window, line 0 its address
    sky_lo, sky_t = mspace.window(20, 1, bytes([0xAA]) * 20)
    eq["TOPSKYROW"] = sky_t * 256 + sky_lo
    # the status bar's arrow strips in MARIA's ROM too (StInit made them in
    # cart RAM's page heads at the first clear: FINDINGS "The CPU's data out
    # of cart RAM"): a 10 x 7 window, each row the player's 5 bytes and the
    # foe's 5; the zone's top line at page ST_HI + 6
    st_lo, st_t = mspace.window(10, 7, bytes(b for r in range(7) for b in
                                             L.ST_PATP[5 * r:5 * r + 5] + L.ST_PATF[5 * r:5 * r + 5]))
    eq.update({"ST_HI": st_t - 6, "ST_PLO": st_lo, "ST_FLO": st_lo + 5})
    F.check_maria(mspace.get, f_rec, f_pre, f_tall)
    for n, key in f_key.items():
        r = f_rec[n] + (f_rec[n + "/m"] if key[0] == "head" else b"")
        at = f_rat[key] - artb.base
        if bytes(artb.data[at:at + len(r)]) not in (bytes(len(r)), r):
            raise SystemExit("fighters: %s shares a record that differs" % n)
        artb.data[at:at + len(r)] = r
    # bank 0's window block: the shared one, its TS pages (levels 1-3's top
    # data elsewhere) the title's and story's own (titlemaria7800)
    # and bank 4's (scene 4, the finale): the ending's text the same way, its
    # characters and maps where the story's are (the far code's tables the
    # same in both pages)
    ts_win, ts_taken = {}, {}
    for sc in (0, 4):
        # (V2: the scene's own window, the text first; its level's graphics
        # after, around it)
        w = bytearray(BANK) if L.V2 else bytearray(mspace.data[:BANK])
        for p in L.TS_PAGES:
            w[(p - 0x80) * 256:(p - 0x7F) * 256] = bytes(256)
        e, t, info = TM.layout(w, list(L.TS_PAGES), tobj, sc)
        if sc == 0:
            ts_eq, ts_tab = e, t
        elif e["TS_CB"] != ts_eq["TS_CB"]:          # (the maps: line L at the same place in both)
            raise SystemExit("the ending's characters not where the story's are")
        tb_ = L.ENDING_BANK if L.V2 and sc == 4 else L.SCENE_BANK[sc]     # (V2: the ending's page)
        ts_win[tb_] = w
        ts_taken[tb_] = set(TM.TAKEN)
        print("%s in bank %d's MARIA copy: %s" % ("the title and story" if sc == 0 else "the ending", tb_, info))
    eq.update(ts_eq)
    src += "\n;;; FAR04 (TS_TAB)\n" + "\n".join(ts_tab) + "\n"
    print("fighters in MARIA's ROM: %d pre-cut parts, %d tall images; %d bytes of its 32K free; "
          "%d bytes of records in the art bank" % (len(f_pre), len(f_tall), mspace.free_bytes(),
                                                   sum(len(f_rec[n]) * (2 if k[0] == "head" else 1)
                                                       for k, n in {k: n for n, k in f_key.items()}.items())))
    with open(os.path.join(os.path.dirname(out_path), "karateka7800.topdata.json"), "w") as f:
        json.dump({"%s/%d" % (",".join(map(str, sc)), si): [p.hex() for p in pages]
                   for (sc, si), pages in top_data.items()}, f)
    top_f["NTI"] = nt_i
    # the story's glyphs (StoryGlyphP): the game's offsets into the small-sprite
    # block ($06F4/$0714, the same in every scene), read with its image's bank in
    m0 = D.memory(0)
    gly = [(m0[0x06F4 + i], m0[0x0714 + i]) for i in range(32)]
    for sc in L.SCENES:
        if [(D.memory(sc)[0x06F4 + i], D.memory(sc)[0x0714 + i]) for i in range(32)] != gly:
            raise SystemExit("the glyph offsets $06F4/$0714 differ in scene %d" % sc)
    # the font's advance tables ($0734 columns, $0754 eighths: the story's
    # templates, StoryInit, in the top bank), the same in every scene
    adv = [(m0[0x0734 + i], m0[0x0754 + i]) for i in range(32)]
    for sc in L.SCENES:
        if [(D.memory(sc)[0x0734 + i], D.memory(sc)[0x0754 + i]) for i in range(32)] != adv:
            raise SystemExit("the advance tables $0734/$0754 differ in scene %d" % sc)
    # the fighters' parts' records (in the art bank: fighters7800): each lower
    # pose's and upper pose's (torso), plain and mirrored; the heads' by scene
    # (FT_HVAR, FT_HV24 each scene's first: 24 a scene, the player's three
    # then each type's; $FF none) and each head's record pair (FT_HT*)
    fa = lambda n: f_rat[f_key[n]]
    hv_scenes = sorted(set(F.SCENE_OF.values()))
    hvar = [f_heads.index(f_hvar[(sc, i)]) if (sc, i) in f_hvar else 0xFF for sc in hv_scenes for i in range(24)]
    src += ("\n;;; FARART (FT_LOW)\nFT_LOWLO:\n" + "\n".join(by([fa("low%d" % x) & 0xFF for x in range(42)]))
            + "\nFT_LOWHI:\n" + "\n".join(by([fa("low%d" % x) >> 8 for x in range(42)]))
            + "\nFT_LOWMLO:\n" + "\n".join(by([fa("low%d/m" % x) & 0xFF for x in range(42)]))
            + "\nFT_LOWMHI:\n" + "\n".join(by([fa("low%d/m" % x) >> 8 for x in range(42)]))
            + "\nFT_TORLO:\n" + "\n".join(by([fa("torso%d" % y) & 0xFF for y in range(38)]))
            + "\nFT_TORHI:\n" + "\n".join(by([fa("torso%d" % y) >> 8 for y in range(38)]))
            + "\nFT_TORMLO:\n" + "\n".join(by([fa("torso%d/m" % y) & 0xFF for y in range(38)]))
            + "\nFT_TORMHI:\n" + "\n".join(by([fa("torso%d/m" % y) >> 8 for y in range(38)]))
            + "\nFT_HTLO:\n" + "\n".join(by([fa(n) & 0xFF for n in f_heads]))
            + "\nFT_HTHI:\n" + "\n".join(by([fa(n) >> 8 for n in f_heads]))
            + "\nFT_HV24:\n" + "\n".join(by([24 * hv_scenes.index(F.SCENE_OF[sc]) for sc in range(7)]))
            + "\nFT_HVAR:\n" + "\n".join(by(hvar))
            + "\nFT_CELLROW:\n" + "\n".join(by([z0 for z0, z1 in F.ZONES]))
            + "\nFT_CELLH:\n" + "\n".join(by([z1 - z0 + 1 for z0, z1 in F.ZONES]))
            # each band row's cell (FtPlain), from FB_TOP
            + "\nFT_ROWCELL:\n" + "\n".join(by([next(i for i, (z0, z1) in enumerate(F.ZONES) if z0 <= r <= z1)
                                                for r in range(L.FB_TOP, L.BAND_ZEND + 1)]))
            + "\nBH_LO:\n" + "\n".join(by([a & 0xFF for a in L.BAND_HEADS]))
            + "\nBH_HI:\n" + "\n".join(by([a >> 8 for a in L.BAND_HEADS])) + "\n")
    eq.update({"FT_PM_9A2A": fa("pmask_9A2A"), "FT_PM_9A2AM": fa("pmask_9A2A/m"),
               "FT_PM_9A18": fa("pmask_9A18"), "FT_PM_9A18M": fa("pmask_9A18/m"),
               "FT_STAR_942A": fa("star_942A"), "FT_STAR_94E6": fa("star_94E6")})
    if L.V2:
        eq.update({"FT_PC_%d" % k: fa("pc_%d" % k) for k in range(len(L.PC_TIPS_LO))})
        eq["FT_PC_BAR"] = fa("pc_bar")
    if L.IMG_BANK != L.TOP_BANK:
        raise SystemExit("StoryInit (the top bank) reads the glyphs' image (IMG_BANK) in its own bank")
    src += "\n;;; FARART (TOP_NTLO)\nTOP_NTLO:\n" + "\n".join(by(nt_lo)) + "\n"
    src += "\n;;; FARART (TOP_NTHI)\nTOP_NTHI:\n" + "\n".join(by(nt_hi)) + "\n"
    def top_src():          # (V2: after the windows, where the sets' columns and pages are known)
        s_ = ""
        for k, vals in top_f.items():
            # (in the top bank, with the code that reads them; V2: by scene
            # group, each group's range in its own page at one base, FARSL)
            kind = "FARSL" if L.V2 else "FARART"
            s_ += "\n;;; %s (TOP_%s)\nTOP_%s:\n" % (kind, k, k) + "\n".join(by(vals)) + "\n"
        s_ += "\n;;; FARART (TOPSCN)\nTOPSCN_FIRST:\n" + "\n".join(by(top_first)) + "\nTOPSCN_N:\n" + "\n".join(by(top_n)) + "\nTOPSCN_A:\n" + "\n".join(by(top_a)) + "\n"
        s_ += "\n;;; FARART (TOPSCN_PB)\nTOPSCN_PB:\n" + "\n".join(by(top_pb)) + "\nTOPSCN_PBA:\n" + "\n".join(by(top_pba)) + "\n"
        return s_
    if not L.V2:
        src += top_src()
    src += "\n;;; FARART (TOPSCN_F)\nTOPSCN_FF:\n" + "\n".join(by(fill_first)) + "\nTOPSCN_FN:\n" + "\n".join(by(fill_n)) + "\n"
    src += "".join(fill_src.values())
    # --- level 1 without the blitter (port/l1scene7800.py; FINDINGS "Level 1
    # without the blitter: the data and the plan"): its play lists' zones as
    # the tables assume them; its windows' layout in the bitmap's pages; the
    # generator's tables (the shapes' in bank L1_HOME, the zone parts' in the
    # fixed bank), its output checked against the layout
    # Levels 3 and 4 the same way (FINDINGS "Levels 2-4 without the
    # blitter"): each scene page's object set (l1scene7800.SETS) made alone,
    # then one table for them all (the shapes in their images' low bytes'
    # order, each with its set; the zone parts and zones numbered on from
    # the sets before)
    l1read = set()                              # (V2: the scene pages' bytes the build reads)
    l1snap = {}                                 # (and their bytes, once the release below gives them back)

    def l1get(bank, a):
        if a < 0x8000:                          # (an image the load carves into console RAM: its
            for s_ in L.PAGE_SCENES:            # source in the scene's page; the cliff fall's,
                if L.SCENE_BANK[s_] != bank:    # $1E00 at $1900: FINDINGS "Recording 02")
                    continue
                for lo_, hi_, ram_ in L.CARVE_SDATA.get(s_, []):
                    if ram_ <= a < ram_ + hi_ - lo_:
                        x_ = lo_ + a - ram_
                        a = [n_ + (x_ - rlo) for rn, rlo, rhi, n_, w in L.REGIONS if rlo <= x_ < rhi][0]
                        break
                else:
                    continue
                break
            else:
                raise SystemExit("l1get: $%04X in bank %d: not a carved image" % (a, bank))
        if L.V2 and bank == L.ART_BANK:         # (the art bank's images: the shadow)
            return art_src.data[a - 0x8000]
        if bank in l1snap:
            return l1snap[bank][a - 0x8000]
        if L.V2 and bank in page_src:
            l1read.add((bank, a))
            return page_src[bank][a - 0x8000]
        l1read.add((bank, a))
        return banks[bank].data[a - 0x8000]
    # (the tiles sets' character sets, l1world7800.Tiles: each its worlds,
    # CHBASE and first byte; their line pages and map rows in the set's cart
    # RAM, l1maps: (set, map row) -> its address)
    tsets = {}
    for st in LS.SETS:
        if st.tiles:
            LS.use(st)
            tsets[st.sid] = [(LW.Tiles(l1get, LS.ZONES, [os.path.join(LW.HERE, p) for p in
                                                        ([path] if isinstance(path, str) else path)], worlds, lo,
                                     drop=LS.L1_DROP),
                              chb + (0x40 if L.V2 else 0), lo)          # (V2: in the scene's MARIA window)
                             for path, worlds, chb, lo in st.tilesets]
    LS.use(LS.L1SET)
    l1tiles = tsets[0][0][0]
    l1maps = {}

    akposes = AK.load()                         # (Akuma's and the hawk's poses: akpose7800)
    akp = {}

    def l1reserve(sid):
        def pre(pg):
            for t, chb, lo in tsets[sid]:
                for o, data in enumerate(t.pages()):
                    pg.reserve(chb + o, lo, data)
            if L.V2:        # (V2: the set's scenes' top data, 15 lines, in its own window: TopLoadSet's S_TPB its top page)
                for key in sorted(k for k in top_sets if set(k[0]) & set(LS.SETS[sid].scenes)):
                    width = top_sets[key][2]
                    data = b"".join(bytes(top_data[key][L.TOP_ZONE - 1 - g][L.TOP_DLO:L.TOP_DLO + width])
                                     for g in range(L.TOP_ZONE))
                    top_vplace[key] = pg.put(L.TOP_ZONE, width, data)
            rows = set(t.short(r)[0] for t, chb, lo in tsets[sid] for r in t.rows.values())
            pref = [b for b in LS.SETS[sid].win_blocks if b[0][0] == 0x54]     # (levels 3 and 4: $54-$56 first)
            for row in sorted(rows, key=lambda r: (-len(r), r)):     # (in a fixed order)
                t, c = pg.put(1, len(row), row, pref)
                l1maps[(sid, row)] = t * 256 + c
            # (then the set's scene's poses' cells: the load cuts them)
            sc = LS.SETS[sid].scenes[0]
            if sc in akposes:
                akp[sid] = AK.reserve(pg, l1get, sc, akposes[sc])
        return pre
    sets = []
    for st in LS.SETS:
        LS.use(st)
        if L.V2:            # (its bank's text's bytes taken: banks 0 and 4)
            wbank = L.SCENE_BANK[st.scenes[0]]
            tk = ts_taken.get(wbank, set())
            LS.PRE_USED = {p: bytearray(1 if p * 256 + c in tk else 0 for c in range(256)) for p in range(0x80, 0xC0)}
        for sc in st.scenes:
            for at in st.lists:
                if at not in xdl.get(sc, ()):
                    raise SystemExit("%s: scene %d has no list $%04X" % (st.name, sc, at))
                d = describe(mem[sc], at)[0]
                if not os.environ.get("NO_DLI_SPACE"):
                    d = space_dlis(d)
                if LS.buffer_zones(d) != st.zones:
                    raise SystemExit("%s: scene %d list $%04X's zones %s, not its set's"
                                     % (st.name, sc, at, LS.buffer_zones(d)))
        lay, pg = LS.layout(l1get, st.inventory(), pre=l1reserve(st.sid) if st.tiles else None)
        f, ent = LS.tables(lay)
        for a, v in LS.generate(l1get, f, ent).items():
            if pg.data[a >> 8][a & 0xFF] != v:
                raise SystemExit("%s: the generator's twin makes $%02X at $%04X, the layout $%02X"
                                 % (st.name, v, a, pg.data[a >> 8][a & 0xFF]))
        sets.append((st, lay, pg, f, ent, list(LS.PARTS)))
        print("%s: %d shapes, %d windows; %d bytes of cart RAM, %d free" % (
            st.name, len(f["SLO"]), sum(len(p) for sh, w, p in lay), pg.size() - pg.free(), pg.free()))
        if st.sid == 0:
            l1lay, l1pg = lay, pg
    LS.use(LS.L1SET)
    if L.V2:                # (the top data's places: each piece's zone columns, each scene's top page)
        if set(top_vplace) != set(top_sets):
            raise SystemExit("V2: top data with no set's window: %s" % sorted(set(top_sets) - set(top_vplace)))
        for key, (t, c) in sorted(top_vplace.items()):
            i0, i1, width = top_sets[key]
            for i in range(i0, i1):
                for zk in zkeys:
                    if top_f[zk][i] != 0xFF:
                        top_f[zk][i] += c - L.TOP_DLO
            for s in key[0]:
                (top_pba if key[1] else top_pb)[s] = t
        if joint_at:            # (level 2's joints: their columns for L2JEmit; the plain one's
            for m_, nm in ((0, "P"), (1, "M")):   # slices $FE, its mark: FINDINGS "Level 2's windows")
                i_ = joint_at[m_]
                for z, zk in enumerate(zkeys):
                    eq["J_%sZ%d" % (nm, z)] = top_f[zk][i_]
                eq["J_%sZ4O" % nm] = top_f["Z4O"][i_]
                eq["J_%sPALW" % nm] = top_f["PALW"][i_]
            for zk in zkeys:
                if top_f[zk][joint_at[0]] != 0xFF:
                    top_f[zk][joint_at[0]] = 0xFE
        print("V2: top data in the scenes' windows: %s" % ", ".join(
            "%s%s %d columns at $%02X%02X" % (",".join(map(str, k[0])), "/alt" if k[1] else "", top_sets[k][2], t - L.TOP_ZONE + 1, c)
            for k, (t, c) in sorted(top_vplace.items())))
        src += top_src()
    # each scene's load as the build knows it (FINDINGS "The ROM by scene:
    # step 1"): cart RAM $4000-$7FFF after the load, 16K of bytes and 16K of
    # flags a scene (L.SCENES' order): 1 the set's tiles, map rows and
    # windows (Pages), 2 a pose's cell (the load cuts it: not known here), 3
    # the black block (FtBlack); 0 not the build's. To <cart>.loadimg, for
    # probes/loadcmp.py
    limg = bytearray()
    lbase = 0x8000 if L.V2 else 0x4000          # (V2: in the scene page's own MARIA window)
    for sc in L.SCENES:
        data, flag = bytearray(0x4000), bytearray(0x4000)
        for st, lay, pg, f, ent, parts in sets:
            if sc not in st.scenes:
                continue
            # (only the bytes the set's Pages took: in its blocks, and the
            # tiles' characters at the pages' heads, reserved)
            for pages, lo, hi in st.win_blocks:
                for p in pages:
                    for b in range(lo, hi):
                        if (pg.used[p][b] and p * 256 + b >= lbase
                                and p * 256 + b not in ts_taken.get(L.SCENE_BANK[sc], ()) if L.V2 else
                                pg.used[p][b] and p * 256 + b >= lbase):     # (V2: not its text's, marked taken)
                            data[p * 256 + b - lbase] = pg.data[p][b]
                            flag[p * 256 + b - lbase] = 1
            for ad in pg.reserved:
                if ad >= lbase:
                    data[ad - lbase] = pg.data[ad >> 8][ad & 0xFF]
                    flag[ad - lbase] = 1
            for pose in akp.get(st.sid, []):          # (the load's cut, akpose7800.cut: flag 2)
                for ad, v in AK.cut(l1get, pose, st.scenes[0]).items():
                    data[ad - lbase] = v
                    flag[ad - lbase] = 2
        if not L.V2:        # (the black block: dead, and in no V2 window)
            for p in range(L.FT_P0, L.FT_PTOP + 1):
                for k in range(L.FT_BLKW):
                    data[p * 256 + L.FT_BLKCOL + k - 0x4000] = 0xAA
                    flag[p * 256 + L.FT_BLKCOL + k - 0x4000] = 3
        if L.V2 and sc in L.PAGE_SCENES:          # (into the scene page's MARIA window, around its text)
            wb = ts_win.setdefault(L.SCENE_BANK[sc], bytearray(BANK))
            tk = ts_taken.get(L.SCENE_BANK[sc], set())
            for k in range(0x4000):
                if flag[k]:
                    if 0x8000 + k in tk and wb[k] != data[k]:
                        raise SystemExit("V2: scene %d's level graphics over its text at $%04X" % (sc, 0x8000 + k))
                    if wb[k] and wb[k] != data[k] and 0x8000 + k not in tk:
                        raise SystemExit("V2: bank %d's window: two scenes differ at $%04X" % (L.SCENE_BANK[sc], 0x8000 + k))
                    wb[k] = data[k]
        limg += data + flag
    with open(os.path.splitext(out_path)[0] + ".loadimg", "wb") as fimg:
        fimg.write(bytes(limg))
    # (V2: the scene pages' images the build turned into windows, poses and
    # characters (l1get's reads) given back: the generators read them at the
    # loads, and the results are in MARIA's ROM now. Not a byte any scene in
    # the page has an instruction, label or relocation in: FINDINGS "The ROM
    # by scene: step 3")
    if L.V2:
        rel = 0
        # (not Akuma's and the hawk's images' and masks' headers: FtPlain reads
        # their rows and width in play, the pose pre-cut or not)
        keep_hdr = {(AK.image_bank(sc, x), x + k) for sc, poses in akposes.items()
                    for img, msk, fl, row in poses for x in (img, msk) if x for k in (0, 1)}
        for b in sorted({bk for bk, ad in l1read}):
            l1snap[b] = bytes(banks[b].data)
            here = [t for t in L.SCENES if L.SCENE_BANK[t] == b]
            ms = [link["scenes"][t]["resolver"].m for t in here]
            labs = {v for m in ms for v in m.symbols.values()}
            kept = {n_ + (x - rlo) for s_ in L.PAGE_SCENES if L.SCENE_BANK[s_] == b       # (layout7800's keeps)
                    for lo, hi in L.V2_CODE_KEEP + L.V2_KEEP_BY_SCENE.get(s_, []) for x in range(lo, hi)
                    for rn, rlo, rhi, n_, w_ in L.REGIONS if rlo <= x < rhi}
            for ad in sorted(x for bk, x in l1read if bk == b):
                off = ad - banks[b].base
                if not banks[b].used[off] or ad in labs or any(ad in m.insn or ad in m.reloc for m in ms)                         or (b, ad) in keep_hdr or ad in kept:
                    continue
                banks[b].release(ad, 1, "released: a window's source $%04X" % ad)
                rel += 1
            print("V2: bank %d: %d bytes free after the release" % (b, sum(1 for x in banks[b].used if not x)))
        print("V2: %d bytes of the windows' sources given back in the scene pages" % rel)
    # one table: the shapes by set, each set's in their images' low bytes'
    # order (the capture's lookup, L1K_F32: a block of 32 a set), each set's
    # first and end (L1L_KB, L1L_KE: an instance keeps its shape less its
    # set's first, 127 a set; FINDINGS "More shapes"); parts and zones
    # numbered on from the sets before
    zbase, pbase, gparts = [], [], []
    for st, lay, pg, f, ent, parts in sets:
        zbase.append(sum(len(s[0].zones) for s in sets[:len(zbase)]))
        pbase.append(len(gparts))
        gparts += [(zi + zbase[-1],) + p[1:] for p in parts for zi in [p[0]]]
    order = sorted((st.sid, f["SLO"][i], k, i) for k, (st, lay, pg, f, ent, parts) in enumerate(sets)
                   for i in range(len(f["SLO"])))
    l1f = {key: [] for key in sets[0][3]}
    l1f["SET"] = []
    l1ent = []
    for sid, lo, k, i in order:
        f = sets[k][3]
        for key in f:
            v = f[key][i]
            if key == "P0":
                v += pbase[k]
            elif key in ("ZA", "ZE"):
                v += zbase[k]
            l1f[key].append(v)
        l1f["SET"].append(sets[k][0].sid)
        l1ent.append(sets[k][4][i])
    l1sets = [(st, zbase[k], zbase[k] + st.zbot) for k, (st, lay, pg, f, ent, parts) in enumerate(sets)]
    l1q_tab = {"L1Q_HM1": [p[2] - 1 for p in gparts],
               "L1Q_ZP0": [next(i for i, p in enumerate(gparts) if p[0] == z)
                           for z in range(sum(len(s[0].zones) for s in sets))],
               "L1Q_ZNP": [sum(1 for p in gparts if p[0] == z)
                           for z in range(sum(len(s[0].zones) for s in sets))]}
    # each shape a record (its flags, width, first part, entries; then its
    # entries: its image's address, row, limit and past its last row only in
    # the capture's arrays, L1K_*), L1S_R each one's address
    nsid = max(st.sid for st in LS.SETS) + 1
    kb = [next((j for j, s in enumerate(l1f["SET"]) if s == sid), 0) for sid in range(nsid)]
    ke = [kb[sid] + l1f["SET"].count(sid) for sid in range(nsid)]
    f32 = []
    for sid in range(nsid):
        lo = [(j, l1f["SLO"][j]) for j in range(kb[sid], ke[sid])]
        assert [v for j, v in lo] == sorted(v for j, v in lo)
        f32 += [next((j for j, v in lo if v >= 8 * q), 0xFF) for q in range(32)]
    if (len(l1ent) > 255 or max(ke[s] - kb[s] for s in range(nsid)) > 127
            or max(len(e) for e in l1ent) > 2 * LS.L1_NMAX):
        raise SystemExit("level 1: %d shapes (%s a set), %d entry bytes at most; 255, 127 a set and %d"
                         % (len(l1ent), [ke[s] - kb[s] for s in range(nsid)], max(len(e) for e in l1ent),
                            2 * LS.L1_NMAX))
    # (placed now, each record in any free run of bank L1_HOME, the largest
    # first: level 1's page code reads them)
    l1hb = banks[L.L1_HOME]
    l1recs = [bytes([l1f[k][i] for k in ("P0", "NE")] + e)       # (flags and width: L1K_FL, L1K_W)
              for i, e in enumerate(l1ent)]
    l1rat = {}
    def pgfind(n, bk, spr=True):              # (V2: a per-page part: best fit among the runs
        best, run = None, None                # where it fits within one 256-byte page, so its
        for a in range(bk.base, bk.base + BANK + 1):   # branches cross none (a cycle each); else
            f = a < bk.base + BANK and not bk.used[a - bk.base] and not (   # l1find's best fit)
                spr and K.SCENEPAGE_TABLE <= a < K.SCENEPAGE_TABLE + SP_RESERVE)
            if f and run is None:
                run = a
            if not f and run is not None:
                at = run
                if (at & 0xFF) + n > 0x100 and n <= 0x100:
                    at = (at | 0xFF) + 1          # (the next page's start, if still in the run)
                if at + n <= a and (best is None or a - run < best[0]):
                    best = (a - run, at)
                run = None
        return best[1] if best else l1find(n, bk, spr)

    def l1find(n, bk=l1hb, spr=True):         # (around the scene pages' system code, $9420 on;
        best, run = None, None                # the smallest free run it fits: the code's
        for a in range(bk.base, bk.base + BANK + 1):   # pieces need the larger ones;
            f = a < bk.base + BANK and not bk.used[a - bk.base] and not (   # spr False: in its
                spr and K.SCENEPAGE_TABLE <= a < K.SCENEPAGE_TABLE + SP_RESERVE)   # reserve's free tail too)
            if f and run is None:
                run = a
            if not f and run is not None:
                if a - run >= n and (best is None or a - run < best[0]):
                    best = (a - run, run)
                run = None
        return best and best[1]
    # (V2: each set's shapes' records and its slice of every array indexed
    # by shape in its scene's page, the array's one base the same in every
    # page: the window holds the scene's page in play, and level 1's code at
    # $4000 reads them as before; FINDINGS "The ROM by scene: step 3")
    def setbank(sid):
        return banks[L.SCENE_BANK[LS.SETS[sid].scenes[0]]]

    def pfree(b, lo, hi):
        return all(not b.used[x - b.base] and not (K.SCENEPAGE_TABLE <= x < K.SCENEPAGE_TABLE + SP_RESERVE)
                   for x in range(lo, hi))

    def slice_place(name, vals, unit, what, lo_of=None):
        """vals indexed by shape (unit bytes a shape; lo_of(sid): the set's
        first index and end, default kb, ke): one base, each set's slice in
        its page; the base"""
        rng = lo_of or (lambda sid: (unit * kb[sid], unit * ke[sid]))
        top = max(rng(sid)[1] for sid in range(nsid))
        # (the base that splits the pages' free runs least: each slice's
        # distance to the nearest taken byte on its nearer side, summed; the
        # code placed after wants the runs whole)
        gaps = {}
        for sid in range(nsid):
            b = setbank(sid)
            if b.name in gaps:
                continue
            fr = [not b.used[x] and not (K.SCENEPAGE_TABLE <= b.base + x < K.SCENEPAGE_TABLE + SP_RESERVE)
                  for x in range(BANK)]
            left, right, n_ = [0] * BANK, [0] * BANK, 0
            for x in range(BANK):
                n_ = n_ + 1 if fr[x] else 0
                left[x] = n_
            n_ = 0
            for x in range(BANK - 1, -1, -1):
                n_ = n_ + 1 if fr[x] else 0
                right[x] = n_
            gaps[b.name] = (fr, left, right)
        best = None
        for base in range(0x8000, 0xC000 - top + 1):
            score = 0
            for sid in range(nsid):
                i0, i1 = rng(sid)
                if i1 <= i0:
                    continue
                b = setbank(sid)
                fr, left, right = gaps[b.name]
                x0, x1 = base + i0 - b.base, base + i1 - b.base
                if right[x0] < x1 - x0:          # (not all free)
                    score = None
                    break
                score += min(left[x0] - 1, right[x1 - 1] - 1)
            if score is not None and (best is None or score < best[0]):
                best = (score, base)
                if score == 0:
                    break
        if best is None:
            for b_ in sorted({setbank(s).name for s in range(nsid)}):
                bb = [setbank(s) for s in range(nsid) if setbank(s).name == b_][0]
                print("  %s: free runs %s" % (b_, runs_of(bb, 24)[:12]))
            raise SystemExit("the scene pages: no base for level 1's %s (V2)" % name)
        base = best[1]
        for sid in range(nsid):
            i0, i1 = rng(sid)
            if i1 > i0:
                setbank(sid).place(base + i0, bytes(vals[i0:i1]), "level 1's %s (set %d)" % (what, sid))
        return base

    def runs_of(b, mn=64):
        out, r = [], None
        for x in range(BANK + 1):
            f_ = x < BANK and not b.used[x]
            if f_ and r is None:
                r = x
            if not f_ and r is not None:
                if x - r >= mn:
                    out.append((x - r, "$%04X" % (b.base + r)))
                r = None
        return sorted(out, reverse=True)
    if L.V2 and os.environ.get("V2RUNS"):
        print("V2: bank 1's runs before level 1's data:", runs_of(banks[1])[:10])
    keep1 = None
    # (V2: each scene page's largest runs kept for the per-page copies, FARPG,
    # placed last: the sliced tables and the records would cut them up; about
    # KEEP_PG bytes a page, given back just before)
    keep_pg = []
    if L.V2:
        KEEP_PG = 0
        for bnum in (4,):           # (scene 4's: the tightest, its runs cut short first)
            bk_, got = banks[bnum], 0
            for n_, at_ in runs_of(bk_, 16):
                if got >= KEEP_PG:
                    break
                x = int(at_[1:], 16)
                if K.SCENEPAGE_TABLE <= x < K.SCENEPAGE_TABLE + SP_RESERVE:
                    continue
                n_ = min(n_, KEEP_PG - got)
                bk_.place(x, bytes(n_), "kept for the per-page copies")
                keep_pg.append((bk_, x, n_))
                got += n_
    if L.V2:                # (bank 1's largest run kept for level 1's page code, LEVEL1PAGE, placed after)
        b1_ = banks[L.SCENE_BANK[L.LEVEL1_SCENES[0]]]
        n1_, at1_ = runs_of(b1_, 1)[0]
        keep1 = (b1_, int(at1_[1:], 16), min(n1_, 640))     # (its parts: 609 bytes in v1, the largest 426)
        b1_.place(keep1[1], bytes(n1_), "kept for level 1's page code")
    if L.V2:
        for i in sorted(range(len(l1recs)), key=lambda i: -len(l1recs[i])):
            sid = l1f["SET"][i]
            at = l1find(len(l1recs[i]), setbank(sid))
            if at is None:
                raise SystemExit("bank %d: no room for level 1's shape record %d (V2)" % (setbank(sid).name, i))
            setbank(sid).place(at, l1recs[i], "level 1's shape record")
            l1rat[i] = at
    # (the index's room first: the largest piece; filled in once the records
    # are placed. V2: in bank 6 as before, each entry pointing into its set's
    # page, which the window holds whenever the set plays)
    l1ix = l1find(2 * len(l1recs))
    if l1ix is None:
        raise SystemExit("bank %d: no room for level 1's shape index (%d bytes)" % (L.L1_HOME, 2 * len(l1recs)))
    l1hb.place(l1ix, bytes(2 * len(l1recs)), "level 1's shape index")   # (V2 too: one base for its slices found none)
    for i in sorted(range(len(l1recs)), key=lambda i: -len(l1recs[i])) if not L.V2 else ():
        at = l1find(len(l1recs[i]))
        if at is None:
            raise SystemExit("bank %d: no room for level 1's shape record %d (%d bytes)" % (L.L1_HOME, i, len(l1recs[i])))
        l1hb.place(at, l1recs[i], "level 1's shape record")
        l1rat[i] = at
    for i in range(len(l1recs)):
        l1hb.data[l1ix + 2 * i - l1hb.base] = l1rat[i] & 0xFF
        l1hb.data[l1ix + 2 * i + 1 - l1hb.base] = l1rat[i] >> 8
    eq["L1S_R"] = l1ix
    # the arrays, placed the same way: each shape's zones (L1S_ZA, past its
    # last L1S_ZE) beside the records; the capture's (L1K_*: image, row,
    # flags, width, past its last row, limit; the first shape by an image's
    # low byte) in bank L1_CAP, read there and by L1Gen (through L1Fetch)
    l1arr = [(l1hb, "L1S_ZA", l1f["ZA"]), (l1hb, "L1S_ZE", l1f["ZE"])]
    # (the tiles: the loader's stream, L1TLoad: the characters' line pages,
    # then the map rows; each world's map rows' addresses by zone and its
    # origin, K, for the emission: L1Tiles)
    # (each tiles set's stream: its character sets' line pages, then its
    # map rows)
    l1chunks = {}
    for sid, ts in tsets.items():
        ch = [((chb + o) * 256 + lo, d) for t, chb, lo in ts for o, d in enumerate(t.pages()) if d]
        ch += [(at, row) for (s, row), at in sorted(l1maps.items(), key=lambda t: t[1]) if s == sid]
        l1chunks[sid] = ch if not L.V2 else []      # (V2: no stream: the set's bytes are in MARIA's ROM)
    # (in pieces, each a stream of its own and one set's, in the free runs of
    # the banks (MARIA's safe ones first: the load reads them through
    # L1Fetch), the largest chunks first, best fit; the pieces' table L1TSP,
    # each set's from L1L_TS, $FF its end)
    l1runs = []
    # (the levels' pages first, then bank 1, then bank 0 (its MARIA copy
    # holds the title's data, so it mustn't be selected while a level
    # shows, but the load runs under the blank list: tmp-loaddll.lua), bank
    # 6 last: code goes there next; not bank 4, the FAR04 pieces' room with
    # bank 0's, nor bank 5, the top bank's pieces)
    for bk in (() if L.V2 else (3, 2, 1, 4, 0, 5, 6)):
        b = banks[bk]
        run = None
        for a_ in range(0x8000, 0xC001):
            f = a_ < 0xC000 and not b.used[a_ - b.base] and not (K.SCENEPAGE_TABLE <= a_ < K.SCENEPAGE_TABLE + SP_RESERVE)
            if f and run is None:
                run = a_
            if not f and run is not None:
                if a_ - run >= 16:
                    l1runs.append([bk, run, a_ - run, [], None])
                run = None
    # (banks 0 and 4: only their small runs, the large ones kept for the
    # pieces placed after: FAR04's, at one address in both, the load's
    # code, FARL0, Akuma's poses' table, FARL4; bank 6 none: level 1's
    # tables and play code, the hawk's poses' table)
    b5 = max((r for r in l1runs if r[0] == 5), key=lambda r: r[2], default=None)
    l1runs = [r for r in l1runs if not (r[0] == 0 and r[2] > 260) and not (r[0] == 4 and r[2] > 130)
              and r[0] not in (5, 6)]
    if b5 and b5[2] > 350:                  # (bank 5: 350 bytes at its largest run's end, the fast
        l1runs.append([5, b5[1] + b5[2] - 350, 350, [], None])     # fill's old image's room)
    b1 = [r for r in l1runs if r[0] == 1]           # (and bank 1's largest run: level 1's page
    if b1:                                          # code, LEVEL1_SCENES', placed after)
        l1runs.remove(max(b1, key=lambda r: r[2]))
    if os.environ.get("TSIZES"):
        for bk_ in (3, 2, 1, 4, 0, 5, 6):
            rs = sorted((r[2] for r in l1runs if r[0] == bk_), reverse=True)
            print("bank %d: runs %d, %s" % (bk_, sum(rs), rs[:10]))
    l1runs.sort(key=lambda r: -r[2])
    if os.environ.get("TSIZES"):
        for sid in sorted(l1chunks):
            print("set %d's tiles' stream: %d bytes in %d chunks" % (sid, sum(len(LW.stream([c])) - 3 for c in l1chunks[sid]), len(l1chunks[sid])))
        print("free runs (48+):", sum(r[2] for r in l1runs), [(r[0], r[2]) for r in l1runs[:12]])
    # (a run holds any sets' chunks: each set's there a piece of its own, a
    # stream with its end, 3 bytes)
    def used(r):
        return sum(len(LW.stream([c])) - 3 for s, c in r[3]) + 3 * len({s for s, c in r[3]})
    # (sets with the same tiles, at the same places: one stream, the first's)
    same = {}
    for sid in sorted(l1chunks):
        same[sid] = next((s for s in sorted(l1chunks) if s < sid and l1chunks[s] == l1chunks[sid]), sid)
    allc = sorted(((sid, c) for sid in l1chunks if same[sid] == sid for c in l1chunks[sid]),
                  key=lambda t: (-len(t[1][1]), t[0], t[1][0]))
    for sid, (at, d) in allc:
        need = len(LW.stream([(at, d)]))
        fit = [r for r in l1runs if r[2] - used(r) - (0 if any(s == sid for s, c in r[3]) else 3) >= need - 3]
        if not fit:
            raise SystemExit("set %d's tiles: no room for their stream's chunk at $%04X (%d bytes)" % (sid, at, need))
        r = min(fit, key=lambda r: ({1: 1, 5: 2, 0: 3, 4: 4}.get(r[0], 0), r[2] - used(r)))
        r[3].append((sid, (at, d)))
    l1tsp, l1ts = [], {}
    for sid in sorted(l1chunks):
        if same[sid] != sid:
            continue
        l1ts[sid] = len(l1tsp)
        for bk, start_, n, cs, s in l1runs:
            at_ = start_
            for s2 in sorted({s for s, c in cs}):
                st_ = LW.stream([c for s, c in cs if s == s2])
                if s2 == sid:
                    banks[bk].place(at_, st_, "the tiles' stream (set %d)" % sid)
                    l1tsp += [bk, at_ & 0xFF, at_ >> 8]
                at_ += len(st_)
        l1tsp.append(0xFF)
    for sid in l1chunks:
        l1ts[sid] = l1ts[same[sid]]
    if len(l1tsp) > 256:
        raise SystemExit("the tiles' pieces' table: %d bytes, L1TLoad's index takes 256" % len(l1tsp))
    l1stream = bytes(l1tsp)
    # (each world's map rows by zone, its set's zones: L1T_* by L1T_WB (its
    # first row less its set's first zone) + the zone, each as stored (its
    # run cut: L1T_CL/CD, l1world7800.Tiles.short); its flags (bit 7 a
    # room: not scrolled; bit 6 level 1's structure, L1Mark), CHBASE, the
    # zone its palette L1_PAL starts at ($FF none: level 1's split only),
    # origin K)
    wsets = {}
    for sid, ts in tsets.items():
        for t, chb, lo in ts:
            for w in t.worlds:
                if w in LS.SETS[sid].own:
                    wsets[w] = (sid, t, chb)
    worlds = sorted(wsets, key=lambda w: LW.WORLD_IDS[w])
    if [LW.WORLD_IDS[w] for w in worlds] != list(range(len(worlds))):
        raise SystemExit("the tiles' worlds: their numbers aren't their order")
    l1rows, wb, l1rsid = [], [], []
    for w in worlds:
        sid, t, chb = wsets[w]
        nz = len(LS.SETS[sid].zones)
        wb.append((len(l1rows) - zbase[sid]) & 0xFF)
        for z in range(nz):
            row, cl, cd = t.short(t.rows[(w, z)])
            l1rows.append((t, l1maps[(sid, row)], row, cl, cd))
            l1rsid.append(sid)
    if len(l1rows) > 256:
        raise SystemExit("the tiles' map rows: %d, L1Tiles' index takes 256" % len(l1rows))
    # (each world's rows by zone an index, L1T_IX, into the distinct rows: the
    # rooms share theirs, levels 3's and 4's the same maps)
    urows, l1ix = [], []
    for r in l1rows:
        k = (r[1], r[3], r[4]) + r[0].extent(r[2])
        hit = next((i for i, u in enumerate(urows) if (u[1], u[3], u[4]) + u[0].extent(u[2]) == k), None)
        if hit is None:
            hit = len(urows)
            urows.append(r)
        l1ix.append(hit)
    l1ix_ = list(l1ix)          # (each row position's distinct row: V2's slices by set)
    l1rows_all, l1rows = l1rows, urows
    palz = next(i for i, (r, h) in enumerate(LS.L1SET.zones) if r >= L.L1_PALROW)
    l1arr += [(banks[L.L1_LDB], "L1TSP", l1tsp),                   # (the load's: L1TLoad)
              (l1hb, "L1T_LO", [r[1] & 0xFF for r in l1rows]), (l1hb, "L1T_HI", [r[1] >> 8 for r in l1rows]),
              (l1hb, "L1T_FB", [r[0].extent(r[2])[0] for r in l1rows]),
              (l1hb, "L1T_LB", [r[0].extent(r[2])[1] for r in l1rows]),
              (l1hb, "L1T_CL", [r[3] for r in l1rows]), (l1hb, "L1T_CD", [r[4] for r in l1rows]),
              (l1hb, "L1T_IX", l1ix),
              (l1hb, "L1T_WB", wb),
              (l1hb, "L1T_FL", [(0x80 if w in LW.FIXED else 0) | (0x40 if w in LW.STRUCT else 0) for w in worlds]),
              (l1hb, "L1T_CB", [wsets[w][2] for w in worlds]),
              (l1hb, "L1T_PZ", [zbase[0] + palz if wsets[w][0] == 0 else 0xFF for w in worlds]),
              (l1hb, "L1T_KL", [wsets[w][1].k[w] & 0xFF for w in worlds]),
              (l1hb, "L1T_KH", [wsets[w][1].k[w] >> 8 for w in worlds])]
    # (the sets' world markers, L1Blit's: image, row ($FF any), kind ($FF
    # any), world ($80: level 1's structure, L1Mark; $C0: found as its
    # column shape; bit 6: only out of a room), set)
    mk = [(st.sid, src, row, kd, w, cond) for st in LS.SETS if st.sid in LS.SETS_ON
          for src, row, kd, w, cond in st.markers]
    l1arr += [(banks[L.L1_CAP], "L1MK_SET", [m[0] for m in mk]),
              (banks[L.L1_CAP], "L1MK_SLO", [m[1] & 0xFF for m in mk]),
              (banks[L.L1_CAP], "L1MK_SHI", [m[1] >> 8 for m in mk]),
              (banks[L.L1_CAP], "L1MK_ROW", [0xFF if m[2] is None else m[2] for m in mk]),
              (banks[L.L1_CAP], "L1MK_KD", [0xFF if m[3] is None else m[3] for m in mk]),
              (banks[L.L1_CAP], "L1MK_W", [0x80 if m[4] is None else 0xC0 if m[4] == "column"
                                           else LW.WORLD_IDS[m[4]] | (0x40 if m[5] else 0) for m in mk])]
    eq["L1MK_N"] = len(mk)
    eq["L1_CHB"] = L.L1_CHB
    eq["L1_PALB"] = L.L1_PAL << 5
    eq["BL_SHV"], eq["BL_MODE"] = L.BL_SHV, L.BL_MODE
    eq.update({"TP_BLD": L.TP_BLD, "TP_SG": L.TP_SG, "TP_SGP": L.TP_SGP, "TP_SO": L.TP_SO, "TP_DLL": L.TP_DLL})
    for k in range(7):
        for nm, seg in (("TPSC", L.TPSEG_A), ("TPSD", L.TPSEG_B), ("TPSE", L.TPSEG_S0A), ("TPSF", L.TPSEG_S0B)):
            lo, hi = seg[k] if k < len(seg) else (0, 0)
            eq["%s%d" % (nm, k)], eq["%s%dE" % (nm, k)] = lo, hi
    eq["L1_PALR"] = 0x21 + 4 * L.L1_PAL
    eq["L1_PALZ"] = next(i for i, (r, h) in enumerate(LS.ZONES) if r >= L.L1_PALROW)
    eq["L1_ZBOT"] = LS.ZBOT
    eq["DLI_FIRST"] = DLI_FIRST
    l1arr += [(banks[L.L1_CAP], "L1K_" + k, l1f[k]) for k in ("SLO", "SHI", "ROW", "FL", "ROWE")]
    l1arr += [(banks[L.L1_LDB], "L1K_LIM", l1f["LIM"])]           # (the load's only: L1Gen)
    # (the width; bit 7: in front of the fighters, the emission's pass 2)
    l1arr += [(banks[L.L1_CAP], "L1K_W", [w | (0x80 if fr >= 2 else 0) | (0x40 if fr == 3 else 0) | (0x20 if fb else 0)
                                           for w, fr, fb in zip(l1f["W"], l1f["FR"], l1f["FB"])])]   # (bit 5, V2: L1Fill)
    l1arr += [(banks[L.L1_CAP], "L1K_F32", f32)]
    PERSHAPE = {"L1S_ZA", "L1S_ZE", "L1K_SLO", "L1K_SHI", "L1K_ROW", "L1K_FL", "L1K_ROWE", "L1K_W"}
    # (V2: each set's ranges in the tables indexed otherwise: the distinct map
    # rows its zones use (levels 3 and 4 share theirs: in different pages),
    # its worlds' rows by zone (L1T_IX), its block of 32 (L1K_F32))
    def _rng(xs):
        return (min(xs), max(xs) + 1) if xs else (0, 0)
    _rows = {s: _rng([l1ix_[p] for p in range(len(l1rsid)) if l1rsid[p] == s]) for s in range(nsid)}
    _pos = {s: _rng([p for p in range(len(l1rsid)) if l1rsid[p] == s]) for s in range(nsid)}
    V2_BYSET = dict({k: (lambda s: _rows[s]) for k in ("L1T_LO", "L1T_HI", "L1T_FB", "L1T_LB", "L1T_CL", "L1T_CD")},
                    L1T_IX=lambda s: _pos[s], L1K_F32=lambda s: (32 * s, 32 * s + 32))
    for bk, name, v in l1arr:
        if L.V2 and keep1 and name not in PERSHAPE | {"L1K_F32", "L1K_LIM"} and bk is not keep1[0]:
            pass
        if L.V2 and name == "L1K_LIM":
            continue                        # (V2: the generator's only)
        if L.V2 and name in PERSHAPE:       # (V2: per set, sliced: each set's in its page)
            eq[name] = slice_place(name, v, 1, name)
            continue
        if L.V2 and name in V2_BYSET and os.environ.get("V2BYSET"):     # (a what-if: by map row, world
            eq[name] = slice_place(name, v, 1, name, lo_of=V2_BYSET[name])  # and zone, block: bank 4
            continue                        # cut to 25-byte runs, the per-page copies don't fit; +104 fixed)
        at = l1find(len(v), bk)
        if at is None:
            raise SystemExit("%s: no room for level 1's %s (%d bytes)" % (bk.name, name, len(v)))
        bk.place(at, bytes(v), "level 1's " + name)
        eq[name] = at
    if keep1:
        keep1[0].release(keep1[1], keep1[2], "kept for level 1's page code: given back")
    if os.environ.get("L1FREE"):
        runs, run = [], None
        for a in range(l1hb.base, l1hb.base + BANK + 1):
            f = a < l1hb.base + BANK and not l1hb.used[a - l1hb.base]
            if f and run is None:
                run = a
            if not f and run is not None:
                if a - run >= 16:
                    runs.append((a - run, "$%04X" % run))
                run = None
        print("bank %d free after level 1's tables: %s (%d)" % (L.L1_HOME, sorted(runs, reverse=True), sum(n for n, r in runs)))
    l1ptab = []
    for k, i in (("Z0", 1), ("H", 2), ("A", 3), ("E", 4), ("BG", 5)):
        l1ptab += ["L1P_%s:" % k] + by([p[i] for p in gparts])
    src += "\n;;; FARL0 (L1PTAB)\n" + "\n".join(l1ptab) + "\n"     # (the zone parts: L1Gen's)
    # (the poses' tables, bank L1_GEN; each set's in AKP_PL/AKP_PH, the top
    # bank's: AkLook, AkPre)
    akb = {}
    for sid, res in sorted(akp.items()):
        bank = AK.TAB_BANK[LS.SETS[sid].scenes[0]]      # (each set's table and its search in a bank)
        akb[sid] = bank
        kind = {0: "FARL0", 3: "FARL3", 4: "FARL4", L.L1_HOME: "FARL1"}[bank]
        src += AKFIND.replace("FARL4", kind).replace("AkF", "AkF%d_" % sid).replace("AkFind", "AkFind%d" % sid)
        chunks = AK.table(res)
        for k, ch in enumerate(chunks):
            nxt = "AKP_T%d_%d" % (sid, k + 1) if k + 1 < len(chunks) else None
            src += ("\n;;; %s (AKP_T%d_%d)\nAKP_T%d_%d:\n" % (kind, sid, k, sid, k)
                    + "\n".join(by([len(ch), "<" + nxt if nxt else "0", ">" + nxt if nxt else "0"]
                                    + [v for b in ch for v in b])) + "\n")
        print("set %d: %d poses pre-cut, %d cells, a table of %d bytes in %d chunks" % (
            sid, len(res), sum(len(cs) for p, b, cs in res), sum(len(b) for ch in chunks for b in ch), len(chunks)))
    src += ("\n;;; FARART (AKP_PB)\nAKP_PB:\n" + "\n".join(by([akb.get(s, 0) for s in range(len(LS.SETS))]))
            + "\nAKP_FL:\n" + "\n".join(by([("<AkF%d_ind" % s) if s in akp else "0" for s in range(len(LS.SETS))]))
            + "\nAKP_FH:\n" + "\n".join(by([(">AkF%d_ind" % s) if s in akp else "0" for s in range(len(LS.SETS))])) + "\n")
    src += ("\n;;; FARART (AKP_PTR)\nAKP_PL:\n" + "\n".join(by([("<AKP_T%d_0" % s) if s in akp else "0" for s in range(len(LS.SETS))]))
            + "\nAKP_PH:\n" + "\n".join(by([(">AKP_T%d_0" % s) if s in akp else "0" for s in range(len(LS.SETS))])) + "\n")
    eq["AKP_NOFF"] = 6 if L.V2 else 7           # (a pose's cell count's offset: V2 has no bank byte)
    eq["L1_WBASE"] = LS.WIN_BASE
    eq.update({"L1_NS": len(l1f["SLO"]), "S_L1": L.S_L1, "L1_HOME": L.L1_HOME, "L1_CAP": L.L1_CAP,
               "L1_GEN": L.L1_GEN, "L1_LDB": L.L1_LDB})
    # the sets by scene for L1Load (in the top bank, with it): each scene's set
    # ($FF none: the blitter), each set's first zone, its bottom zones' first
    # (rows 135 on) and its flags (bit 7 the canvas, bit 6 tiles)
    on = {sc: st.sid for st, zb, zt in l1sets for sc in st.scenes if st.sid in LS.SETS_ON}
    lt = ["", ";;; FARART (L1LTAB)", "L1L_SET:"] + by([on.get(sc, 0xFF) for sc in range(7)])
    lt += ["L1L_ZB:"] + by([zb for st, zb, zt in l1sets]) + ["L1L_ZBT:"] + by([zt for st, zb, zt in l1sets])
    lt += ["L1L_SF:"] + by([(0x80 if st.canvas else 0) | (0x40 if st.tiles else 0) | (0x20 if st.vwrap else 0)
                            | (0x10 if st.mask01 else 0) for st, zb, zt in l1sets])
    lt += ["L1L_TS:"] + by([l1ts.get(st.sid, 0) for st, zb, zt in l1sets])          # (its tiles' pieces' first)
    lt += ["L1L_KB:"] + by([kb[st.sid] for st, zb, zt in l1sets])                   # (its shapes' first, end)
    lt += ["L1L_KE:"] + by([ke[st.sid] for st, zb, zt in l1sets])
    lt += ["L1L_RW:"] + by([LW.WORLD_IDS[st.room] if st.room else 0xFF for st, zb, zt in l1sets])   # (its room)
    src += "\n".join(lt) + "\n"
    if [st.sid for st, zb, zt in l1sets] != list(range(len(l1sets))):
        raise SystemExit("the object sets' numbers aren't their order")
    l1q = ["", ";;; FARL1 (L1QTAB)"]               # (read only by L1_HOME's code: in that bank)
    for k, v in l1q_tab.items():
        l1q += ["%s:" % k] + by(v)
    src += "\n".join(l1q) + "\n"
    eq.update(LS.ram_equates(L.L1RAM))
    print("level 1: %d shapes, %d windows; %d tiles' characters, %d map rows (%d bytes); "
          "%d bytes of cart RAM, %d free; tables %d bytes, the tiles' stream %d" % (
        len(l1f["SLO"]), sum(len(p) for sh, w, p in l1lay), len(l1tiles.idx),
        sum(1 for s, r in l1maps if s == 0), sum(len(r) for s, r in l1maps if s == 0), l1pg.size() - l1pg.free(),
        l1pg.free(), 11 * len(l1f["SLO"]) + sum(len(e) for e in l1ent), len(l1stream)))
    pieces = src.split("\n;;; FAR")
    src = pieces[0]

    def assemble_at(lines_in, org, extra_eq):
        lines = ["%s = $%04X" % (k, v) for k, v in sorted(eq.items())] + \
                ["%s = $%04X" % (k, v) for k, v in sorted(extra_eq.items())] + \
                ["    .org $%04X" % org] + lines_in
        a = asm.Assembler()
        try:
            return a.assemble(lines), a.sym
        except asm.AsmError as e:              # (the line itself, for the reader)
            m = re.search(r"line (\d+)", str(e))
            if m and int(m.group(1)) <= len(lines):
                raise SystemExit("%s: %s" % (e, lines[int(m.group(1)) - 1].strip()))
            raise
    rf_code, rf_sym = assemble_at(rf_text, K.RAMFILL_TABLE, {})
    if K.RAMFILL_TABLE + len(rf_code) > L.SMALLDL_AT:
        raise SystemExit("the fast fill's code (%d bytes) runs into the static display lists at $%04X"
                         % (len(rf_code), L.SMALLDL_AT))
    for i, name in enumerate(K.RAMFILL_ENTRIES):
        if rf_sym[name] != K.RAMFILL_TABLE + 3 * i:
            raise SystemExit("fast fill jump table: %s at $%04X" % (name, rf_sym[name]))
    if rf_sym["FpPatch0"] >> 8 != rf_sym["FpPatched"] >> 8:
        raise SystemExit("fast fill: the patch code crosses a page (its table holds low bytes)")
    if rf_sym["FILL_BLK"] >> 8 != rf_sym["FILL_NEXT"] >> 8:
        raise SystemExit("fast fill: the store block crosses a page (FpGo's jump is set by its low byte)")
    # (no image any more: every scene that plays has a set, which captures
    # its fills; the code is assembled for its symbols, the game's patched
    # fill entries' targets, never reached: FINDINGS "The attract loop as
    # tiles")
    # Two passes, so a far piece may call into the main block and the other
    # way round: the main block first with its far labels at a placeholder
    # (every reference between them is an absolute address above $E000, so
    # no instruction changes size), then each piece against the main block's
    # labels, placed; then the main block again with the pieces' real
    # addresses. The largest pieces are placed first.
    # ";;; FAR04 (name)": a piece for scenes 0 and 4 only, placed in their
    # scene pages (banks 0 and 4, the same address in both) instead of the
    # fixed bank
    # ";;; FARART (name)": a piece of the top rows' machinery, in the top
    # bank's free space (L.TOP_BANK: the spare bank, 5; the art bank, 6, it
    # filled first), run with that bank selected (its stubs select it)
    texts = [p.split("\n", 1)[1].splitlines() for p in pieces[1:]
             if not p.startswith(("04", "ART", "L0", "L1", "L2", "L3", "L4", "L9", "LOAD", "COM", "PG", "SL"))]
    textssl = [p.split("\n", 1)[1].splitlines() for p in pieces[1:] if p.startswith("SL")]
    # (";;; FARPG (name)": V2: a copy in every scene page, in parts where its
    # runs are short (split_parts), reached through the scene page's vectors
    # (PgBuildDll, PgTopErase): called with the page in, as every play's code)
    textspg = [p.split("\n", 1)[1].splitlines() for p in pieces[1:] if p.startswith("PG")]
    # (";;; FARCOM (name)": V2: assembled with the scene pages' system code,
    # in every scene page at one address: called as it is, no switch)
    for p in pieces[1:]:
        if p.startswith("COM"):
            sp_text += p.split("\n", 1)[1].splitlines()
    # (";;; FARLOAD (name)": a load's piece: as a FARART one in today's
    # layout; V2: in the loader bank, through LoaderCall)
    textsload = [p.split("\n", 1)[1].splitlines() for p in pieces[1:] if p.startswith("LOAD")]
    textsl0 = [p.split("\n", 1)[1].splitlines() for p in pieces[1:] if p.startswith("L0")]
    textsl4 = [p.split("\n", 1)[1].splitlines() for p in pieces[1:] if p.startswith("L4")]
    textsl3 = [p.split("\n", 1)[1].splitlines() for p in pieces[1:] if p.startswith("L3")]   # (V2: the hawk's poses, bank 3)
    textsl1 = [p.split("\n", 1)[1].splitlines() for p in pieces[1:] if p.startswith("L1")]
    textsl2 = [p.split("\n", 1)[1].splitlines() for p in pieces[1:] if p.startswith("L2")]
    # (";;; FARL9 (name)": V2: a level-1 piece placed after all the others, the
    # poses' tables too, in what's left: FINDINGS "Akuma's red")
    textsl9 = [p.split("\n", 1)[1].splitlines() for p in pieces[1:] if p.startswith("L9")]
    texts04 = [p.split("\n", 1)[1].splitlines() for p in pieces[1:] if p.startswith("04")]
    textsart = [p.split("\n", 1)[1].splitlines() for p in pieces[1:] if p.startswith("ART")]
    if not L.V2:
        textsart, textsload = textsart + textsload, []
    label = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):")
    far_names = {m.group(1) for t in texts + texts04 + textsart + textsl0 + textsl1 + textsl2 + textsl4 + textsl3 + textsl9 + textsload
                  + textspg + textssl for ln in t for m in [label.match(ln)] if m}
    # a label defined twice (in two pieces, or a piece and the main block):
    # each is assembled apart, so the assembler can't see it, and a caller
    # could reach the other one (a second TopCopy did: FINDINGS)
    seen_l = {}
    for t in [src.splitlines()] + texts + texts04 + textsart + textsl0 + textsl1 + textsl2 + textsl4 + textsl3 + textsl9 + textsload + textspg + textssl + [sp_text]:
        for nm in {m.group(1) for ln in t for m in [label.match(ln)] if m}:
            seen_l[nm] = seen_l.get(nm, 0) + 1
    twice = sorted(nm for nm, k in seen_l.items() if k > 1)
    if twice:
        raise SystemExit("system code: labels defined twice: %s" % ", ".join(twice))
    sp_names = {m.group(1) for ln in sp_text for m in [label.match(ln)] if m}
    main_lines = src.splitlines() + tables
    main_code0, main_sym = assemble_at(main_lines, K.SYS_TABLE, {n: 0xF500 for n in far_names | sp_names})
    main_eq = {k: v for k, v in main_sym.items() if k not in eq and k not in far_names and k not in sp_names}
    # the level-1 code in its parts (each in a free run of both pages, the
    # largest first; they call each other only by JSR/JMP, so sizes don't
    # depend on where the others go), then the scene-page code at its fixed
    # address in every scene page
    l1_names = {m.group(1) for part in l1_parts for ln in part for m in [label.match(ln)] if m}
    ph = {n: 0x8000 for n in l1_names}
    sp_far_ph = {n: 0xF500 for n in far_names} if L.V2 else {}
    sp_size = len(assemble_at(sp_text, K.SCENEPAGE_TABLE, dict(main_eq, **ph, **sp_far_ph))[0])
    sp_end = K.SCENEPAGE_TABLE + sp_size
    l1_banks = [banks[b] for b in sorted({L.SCENE_BANK[sc] for sc in L.LEVEL1_SCENES})]

    def own(k, syms):                        # the other parts' labels only
        mine = {m.group(1) for ln in l1_parts[k] for m in [label.match(ln)] if m}
        return {n: v for n, v in syms.items() if n not in mine}

    def l1_free(a):
        return not (K.SCENEPAGE_TABLE <= a < sp_end) and all(not b.used[a - b.base] for b in l1_banks)
    l1_at = {}
    for k in sorted(range(len(l1_parts)), key=lambda k: -len(assemble_at(l1_parts[k], 0x8000, own(k, ph))[0])):
        size = len(assemble_at(l1_parts[k], 0x8000, own(k, ph))[0])
        at = next((a for a in range(0x8000, 0xC000 - size + 1)
                   if all(l1_free(a + i) for i in range(size))), None)
        if at is None:
            runs, run = [], None
            for a in range(0x8000, 0xC001):
                if a < 0xC000 and l1_free(a):
                    run = a if run is None else run
                elif run is not None:
                    runs.append((a - run, run))
                    run = None
            raise SystemExit("level-1 code part %d (%d bytes): no room in the level-1 scene pages (largest: %s)" % (
                k, size, ", ".join("$%04X+%d" % (r, n) for n, r in sorted(runs, reverse=True)[:4])))
        l1_at[k] = at
        for b in l1_banks:
            b.place(at, bytes(size), "level-1 system code")     # reserved; filled below
    l1_sym = {}
    for k, part in enumerate(l1_parts):
        l1_sym.update({n: v for n, v in assemble_at(part, l1_at[k], own(k, ph))[1].items()
                       if n in l1_names and n not in own(k, ph)})
    for k, part in enumerate(l1_parts):
        code_k = assemble_at(part, l1_at[k], own(k, l1_sym))[0]
        for b in l1_banks:
            b.data[l1_at[k] - b.base:l1_at[k] - b.base + len(code_k)] = code_k
        print("level-1 system code $%04X + %d bytes, in scene pages %s" % (
            l1_at[k], len(code_k), ", ".join(str(sc) for sc in L.LEVEL1_SCENES)))
    l2_sym, l2_at = {}, []
    if l2_parts:
        b2_ = banks[L.SCENE_BANK[2]]
        l2_names = {m.group(1) for part in l2_parts for ln in part for m in [label.match(ln)] if m}
        ph2 = dict(main_eq, **{n: 0xF500 for n in far_names | l2_names if n not in main_eq})

        def own2(k):
            mine = {m.group(1) for ln in l2_parts[k] for m in [label.match(ln)] if m}
            return {n: v for n, v in ph2.items() if n not in mine}
        for k, part in enumerate(l2_parts):
            size = len(assemble_at(part, 0x8000, own2(k))[0])
            at = next((a for a in range(0x8000, 0xC000 - size + 1)
                       if all(not (K.SCENEPAGE_TABLE <= a + i < K.SCENEPAGE_TABLE + SP_RESERVE)
                              and not b2_.used[a + i - b2_.base] for i in range(size))), None)
            if at is None:
                raise SystemExit("level-2 page code part %d (%d bytes): no room in bank %d" % (k, size, L.SCENE_BANK[2]))
            b2_.place(at, bytes(size), "level-2 page code")       # (filled in the far pieces' second pass)
            l2_at.append((at, part, size, [b2_]))
        for at, part, size, imgs in l2_at:
            mine = {m.group(1) for ln in part for m in [label.match(ln)] if m}
            l2_sym.update({n: v for n, v in assemble_at(part, at, {n: v for n, v in ph2.items() if n not in mine})[1].items()
                           if n in mine})
            print("level-2 page code $%04X + %d bytes, in scene page 2" % (at, size))
    sp_code, sp_sym = assemble_at(sp_text, K.SCENEPAGE_TABLE, dict(main_eq, **l1_sym, **sp_far_ph))
    if os.environ.get("SPFREE"):              # the free runs every scene page shares
        sb = [banks[L.SCENE_BANK[sc]] for sc in L.PAGE_SCENES]
        run = None
        for a in range(0x8000, 0xC000):
            free = all(not b.used[a - b.base] for b in sb)
            if free and run is None:
                run = a
            if (not free or a == 0xBFFF) and run is not None:
                if a - run >= 32:
                    print("scene pages: $%04X-$%04X free in all (%d bytes)" % (run, a - 1, a - run))
                run = None
        print("scene-page code: %d bytes" % len(sp_code))
        run = None
        for a in range(0xC000, SIG_START + 1):
            free = a < SIG_START and not fixed.used[a - fixed.base]
            if free and run is None:
                run = a
            if not free and run is not None:
                if a - run >= 16:
                    print("fixed bank: $%04X-$%04X free (%d bytes)" % (run, a - 1, a - run))
                run = None
    for sc in L.PAGE_SCENES:
        banks[L.SCENE_BANK[sc]].place(K.SCENEPAGE_TABLE, sp_code, "scene-page system code")
    for i, name in enumerate(K.SCENEPAGE_ENTRIES):
        if sp_sym[name] != K.SCENEPAGE_TABLE + 3 * i:
            raise SystemExit("scene-page jump table: %s at $%04X" % (name, sp_sym[name]))
    print("scene-page system code $%04X + %d bytes, in every scene page" % (K.SCENEPAGE_TABLE, len(sp_code)))
    print("system block: %d bytes, $%04X-$%04X; to engine1 $%04X: %d free" % (
        len(main_code0), K.SYS_TABLE, K.SYS_TABLE + len(main_code0) - 1, L.ENGINE1_AT,
        L.ENGINE1_AT - K.SYS_TABLE - len(main_code0)))
    # The far pieces in two passes as well, so that one may use another's
    # labels: each assembled with the others' labels at a placeholder (every
    # reference between them is an absolute address above $8000, so no
    # instruction changes size) and placed, the largest first; then each
    # again with all the labels known, in its place.
    def own_labels(t):
        return {m.group(1) for ln in t for m in [label.match(ln)] if m}

    def far_ph(t):
        return dict({n: 0xF500 for n in (far_names | sp_names) - own_labels(t)}, **main_eq, **l2_sym)
    sized = [(len(assemble_at(t, 0xF500, far_ph(t))[0]), t) for t in texts]
    far_eq = {k: v for k, v in sp_sym.items() if k in sp_names}     # the scene page's labels too
    far_eq.update(l2_sym)                      # (V2: the level-2 page's)
    far_sym = dict(far_eq)
    far_sym.update(l1_sym)                     # for the symbol file (the probes)
    far_sym.update({k: v for k, v in rf_sym.items() if K.RAMFILL_TABLE <= v < K.RAMFILL_TABLE + len(rf_code) and k not in eq})   # the fast fill's labels
    placed = list(l2_at)                       # (V2: the level-2 page's parts, for the second pass)
    for size, text in sorted(sized, key=lambda st: -st[0]):
        at = (fixed.find(size, 0xC000, K.SYS_TABLE)                        # (around the main block)
              or fixed.find(size, K.SYS_TABLE + len(main_code0), SIG_START))
        if at is None:
            runs, run0 = [], None
            for a in range(0xC000, SIG_START + 1):
                f = a < SIG_START and not fixed.used[a - fixed.base]
                if f and run0 is None:
                    run0 = a
                if not f and run0 is not None:
                    runs.append((a - run0, run0))
                    run0 = None
            print("fixed's free runs now: %s" % ", ".join("$%04X+%d" % (r, n) for n, r in sorted(runs, reverse=True) if n >= 4))
            raise SystemExit("fixed: no room for a far piece (%d bytes; all: %s)" % (
                size, ", ".join("%s %d" % (t[0].split(":")[0] if t else "?", n) for n, t in sized)))
        code_p, sym_p = assemble_at(text, at, far_ph(text))
        fixed.place(at, code_p, "far system code")
        placed.append((at, text, len(code_p), [fixed]))
        new = {k: v for k, v in sym_p.items() if k in own_labels(text)}
        far_eq.update(new)
        far_sym.update(new)
        print("far system code $%04X + %d bytes (%s)" % (at, len(code_p), ", ".join(sorted(new))))

    # the FAR04 pieces: a run free in both scene pages 0 and 4 ($8000-$BFFF)
    b04 = [banks[L.SCENE_BANK[0]], banks[L.SCENE_BANK[4]]]
    for size, text in sorted([(len(assemble_at(t, 0x9000, far_ph(t))[0]), t) for t in texts04], key=lambda st: -st[0]):
        at = next((a for a in range(0x8000, 0xC000 - size + 1)
                   if all(not b.used[a - b.base + i] for b in b04 for i in range(size))), None)
        if at is None:
            raise SystemExit("scene pages 0 and 4: no room for a FAR04 piece (%d bytes)" % size)
        code_p, sym_p = assemble_at(text, at, far_ph(text))
        for b in b04:
            b.place(at, code_p, "scene 0/4 system code")
        placed.append((at, text, len(code_p), b04))
        new = {k: v for k, v in sym_p.items() if k in own_labels(text)}
        far_eq.update(new)
        far_sym.update(new)
        print("scene 0/4 system code $%04X + %d bytes (%s)" % (at, len(code_p), ", ".join(sorted(new))))
    # the FARART pieces: in the top bank's free runs
    artb = banks[L.TOP_BANK]
    def art_size(t):
        try:
            return len(assemble_at(t, 0xA000, far_ph(t))[0])
        except asm.AsmError as e:
            raise SystemExit("FARART piece %s: %s (its line %s)" % (next((ln for ln in t if label.match(ln)), "?").strip(), e,
                                                                   str(e).split()[1].rstrip(":")))
    def fixed_room(size):                   # (the fixed bank's runs around the main block)
        return (fixed.find(size, 0xC000, K.SYS_TABLE)
                or fixed.find(size, K.SYS_TABLE + len(main_code0), SIG_START))

    # (V2) the top pieces' tables (FARSL): a scene group reads only its own
    # pieces' entries, with its page in; each table at one base (TOP_x,Y as
    # ever), each group's pieces numbered from its own first index (TPG<page>:
    # the groups are in different pages, so their numbers may overlap), its
    # entries at base + that index in its page. The search: a base a table
    # (at least a group's length apart) leaving each group some first index
    # whose windows are all free
    if L.V2 and textssl:
        grp = [(g, hi - lo, lo) for g, lo, hi in top_groups if hi > lo]
        if len({g for g, n, lo in grp}) != len(grp):
            raise SystemExit("V2: two top groups in one page")
        okint, feas = {}, {}                # (bit sets: addresses with n free bytes on; first indexes)
        if os.environ.get("V2RUNS"):
            for g, n, lo in grp:
                print("V2: bank %d before the top tables: free %d, runs %s" % (
                    g, sum(1 for x in banks[g].used if not x), runs_of(banks[g], 16)[:14]))
        for g, n, lo in grp:
            u, r, bits = banks[g].used, 0, []
            for x in range(BANK - 1, -1, -1):
                r = 0 if u[x] else r + 1
                bits.append("1" if r >= n else "0")
            okint[g] = int("".join(bits), 2)          # (bit x: address $8000 + x)
            feas[g] = (1 << (256 - n + 1)) - 1       # (an index byte: its pieces' loops count, S_TJ)
        nmax = max(n for g, n, lo in grp)
        bases, chosen = {}, []
        for t in textssl:
            name = next(ln.split(":")[0] for ln in t if label.match(ln))
            best, best_b = 0, None
            for b_ in range(BANK - nmax):
                if any(abs(b_ - c) < nmax for c in chosen):
                    continue
                c_ = min(((okint[g] >> b_) & feas[g]).bit_count() for g, n, lo in grp)
                if c_ > best:
                    best, best_b = c_, b_
            if best_b is None:
                raise SystemExit("V2: no base for %s's slices (%s)" % (name, top_groups))
            for g, n, lo in grp:
                feas[g] &= okint[g] >> best_b
            bases[name] = 0x8000 + best_b
            chosen.append(best_b)
        first_ix = {g: (feas[g] & -feas[g]).bit_length() - 1 for g, n, lo in grp}
        for g, n, lo in grp:
            eq["TPG%d" % g] = first_ix[g]
        for t in textssl:
            name = next(ln.split(":")[0] for ln in t if label.match(ln))
            vals = [v.strip() for ln in t if ln.strip().startswith(".byte") for v in ln.strip()[5:].split(",")]
            base = bases[name]
            for g, n, lo in grp:
                text_ = ["    .byte " + ",".join(vals[lo:lo + n])]
                at = base + first_ix[g]
                code_p, _ = assemble_at(text_, at, far_ph(text_))
                banks[g].place(at, code_p, "the top tables' slices (V2)")
                placed.append((at, text_, len(code_p), [banks[g]]))
            far_eq[name] = far_sym[name] = base
        print("V2: the top tables by scene group: bases %s; first indexes %s" % (
            ", ".join("%s $%04X" % (k[4:], v) for k, v in bases.items()), first_ix))
    v2_left = []
    for size, text in sorted([(art_size(t), t) for t in textsart], key=lambda st: -st[0]):
        at, tb = artb.find(size, 0x8000, 0xC000), artb
        if at is None and L.V2:             # (V2: both fixed: the other one's room)
            at, tb = fixed_room(size), fixed
        if at is None and L.V2 and os.environ.get("V2ALL"):     # (V2ALL=1: on, the misses listed at the end)
            v2_left.append((size, next((ln.split(":")[0] for ln in text if label.match(ln)), "?")))
            continue
        if at is None:
            if os.environ.get("BANKMAP"):
                from collections import Counter as _C
                agg = _C()
                for a__, n__, w in artb.log:
                    agg[w.split(" (")[0].split(" $")[0][:40]] += n__
                for w_, n_ in agg.most_common(40):
                    print("  %6d %s" % (n_, w_))
                print("  free %d" % sum(1 for x in artb.used if not x))
            left = sum(s_ for s_, t_ in sorted([(art_size(t), t) for t in textsart], key=lambda st: -st[0]) if s_ <= size)
            l1left = sum(art_size(t) for t in textsl1 + textsl2)
            print("  the FARART pieces not placed: %d bytes; level 1's code after: %d" % (left, l1left))
            print("  their sizes:", [s_ for s_, t_ in sorted([(art_size(t), t) for t in textsart], key=lambda st: -st[0]) if s_ <= size],
                  "; level 1's:", sorted((art_size(t) for t in textsl1 + textsl2), reverse=True))
            raise SystemExit("the top bank: no room for a FARART piece (%d bytes)" % size)
        code_p, sym_p = assemble_at(text, at, far_ph(text))
        tb.place(at, code_p, "top-bank system code")
        placed.append((at, text, len(code_p), [tb]))
        new = {k: v for k, v in sym_p.items() if k in own_labels(text)}
        far_eq.update(new)
        far_sym.update(new)
        print("top-bank system code $%04X + %d bytes (%s)" % (at, len(code_p), ", ".join(sorted(new)[:3]) + (" ..." if len(new) > 3 else "")))
    if v2_left:
        for b_ in range(5):
            print("  bank %d free %d, runs %s" % (b_, sum(1 for x in banks[b_].used if not x), runs_of(banks[b_], 64)[:6]))
        common_, r_ = [], None
        for x in range(BANK + 1):
            f_ = x < BANK and all(not banks[b_].used[x] for b_ in range(5))
            if f_ and r_ is None:
                r_ = x
            if not f_ and r_ is not None:
                if x - r_ >= 32:
                    common_.append((x - r_, "$%04X" % (0x8000 + r_)))
                r_ = None
        print("  free in every scene page:", sorted(common_, reverse=True), sum(n for n, at in common_))
        free6 = sum(1 for x in artb.used if not x)
        free7 = sum(1 for x in range(BANK) if not fixed.used[x])
        if os.environ.get("V2MAP"):         # (V2MAP=1: what fills the two fixed banks)
            from collections import Counter as _C
            for img_ in (artb, fixed):
                agg = _C()
                for a__, n__, w in img_.log:
                    agg[re.sub(r"[ (].*", "", w.replace("system code", "syscode").replace("top-bank ", "top-bank_")
                               .replace("far ", "far_").replace("level 1's ", "level1_"))[:40]] += n__
                print("  %s (free %d):" % (img_.name, sum(1 for x in img_.used if not x)))
                for w_, n_ in agg.most_common(60):
                    print("    %6d %s" % (n_, w_))
        raise SystemExit("V2: FARART pieces not placed: %d bytes %s; free then: bank 6 %d, the fixed bank %d (before "
                         "its main block)" % (sum(s for s, n_ in v2_left), v2_left, free6, free7))
    # (V2) the FARLOAD pieces: in the loader bank's free runs
    ldb = banks[L.LOADER_BANK]
    if L.V2:            # (the boot's image in the fixed bank: ResetB copies it, any bank in)
        at_sm = fixed_room(len(small_image))
        if at_sm is None:
            raise SystemExit("the fixed bank: no room for the boot's image (%d bytes)" % len(small_image))
        fixed.place(at_sm, small_image, "static display lists' image")
        eq["IMG_SMALLDL"] = at_sm
    if L.V2:            # (in parts, best fit: scene 3's page, around its own; the cuts' labels far names)
        textsload = [pt for t in textsload for pt in split_long(t, make=True)]
        far_names |= set().union(*(own_labels(pt) for pt in textsload))
    for size, text in sorted([(art_size(t), t) for t in textsload], key=lambda st: -st[0]):
        at = l1find(size, ldb) if L.V2 else ldb.find(size, 0x8000, 0xC000)
        if at is None:
            raise SystemExit("the loader bank: no room for a FARLOAD piece (%d bytes)" % size)
        code_p, sym_p = assemble_at(text, at, far_ph(text))
        ldb.place(at, code_p, "loader code")
        placed.append((at, text, len(code_p), [ldb]))
        new = {k: v for k, v in sym_p.items() if k in own_labels(text)}
        far_eq.update(new)
        far_sym.update(new)
        print("loader code $%04X + %d bytes (%s)" % (at, len(code_p), ", ".join(sorted(new)[:3])))
    # (V2) a page with no sky top: TopSky's stub, the same entries; FINDINGS "Run 10"
    SKY_STUB = ["TopSkyGo:", "    LDA #$00", "    STA S_PPD1", "    STA S_PPD2", "    STA S_TSKY",
                "TopSkyOnRun:", "TopSkyOffZone:", "    RTS", "TopSkyOnMark:", "    CLC", "    RTS"]

    def pg_texts(bnum):
        return [SKY_STUB if bnum in L.NO_SKY_PAGES and any(ln.startswith("TopSkyGo:") for ln in t) else t
                for t in textspg]
    # (V2) bank 4's per-page parts held at their best fit before the level-1
    # pieces: the poses' tables' chunks, placed there first, left only runs of
    # under 8 bytes for them (FINDINGS "The hardware test"). Their sizes don't
    # depend on the far labels' values (all absolute): placeholders here
    pg_held = {}
    if L.V2 and textspg:
        for bnum in PG_HOLD:
            pb_ = banks[bnum]
            parts_ = [pt for t in pg_texts(bnum) for pt in split_long(t, PG_MAXLINES_BY_BANK.get(bnum, PG_MAXLINES), PG_MAKE)]
            own_ = set().union(*(own_labels(pt) for pt in parts_))
            ph_ = {n: 0xF500 for n in (far_names | sp_names | set(l2_sym) | own_) if n not in main_eq}
            sz_ = [len(assemble_at(pt, 0x8000, dict(main_eq, **{n: v for n, v in ph_.items() if n not in own_labels(pt)}))[0])
                   for pt in parts_]
            at0_ = {}
            for k in sorted(range(len(parts_)), key=lambda k: -sz_[k]):
                x = pgfind(sz_[k], pb_, bnum != 4)
                if x is None:
                    raise SystemExit("V2: bank %d: no room to hold a per-page part (%d bytes)" % (bnum, sz_[k]))
                pb_.place(x, bytes(sz_[k]), "held for the per-page copies")
                at0_[k] = x
            pg_held[bnum] = [(sz_[k], at0_[k]) for k in range(len(parts_))]
            print("V2: bank %d: %d per-page parts held (%d bytes)" % (bnum, len(parts_), sum(sz_)))
    # the FARL1 and FARL2 pieces (level 1 without the blitter): in banks
    # L1_HOME's and L1_CAP's free runs
    # (V2: no generator, L1Init instead: FARL0 left out; bank 6 full, the
    # fixed bank's room, as the FARART pieces')
    for bk, tl in ((L.L1_GEN, [] if L.V2 else textsl0), (L.L1_HOME, textsl1), (L.L1_CAP, textsl2), (4, textsl4),
                   (3, textsl3), (L.L1_HOME, textsl9)):
        l1b = banks[bk]
        if L.V2:            # (in parts: the fixed bank's runs are short)
            tl = [pt for t in tl for pt in split_parts(t)]
        to_fixed = 0
        for size, text in sorted([(art_size(t), t) for t in tl], key=lambda st: -st[0]):
            at = (l1find(size, l1b) if L.V2 and bk in (3, 4)    # (V2: the poses' tables best fit, scene pages)
                  else l1b.find(size, 0x8000, 0xC000))        # (the scene pages' system code is placed by now)
            l1t = l1b
            if (L.V2 and bk == 4 and to_fixed + size <= AKP_TO_FIXED and any(ln.startswith("AKP_T") for ln in text)
                    and fixed_room(size) is not None):      # (bank 4's: some of its poses' tables in the fixed bank)
                at, l1t = fixed_room(size), fixed
                to_fixed += size
            if at is None and ((L.V2 and bk in (L.TOP_BANK, L.L1_HOME, L.L1_CAP)) or (not L.V2 and bk == L.L1_CAP)):
                # (v1: bank 6 full since the cliff fall's shapes, FINDINGS
                # "Recording 02": L1Call has bank 6 in, so a piece in the fixed
                # bank reads its tables as well; V2: bank 6 always at $4000,
                # full since L1PartW's check, FINDINGS "Akuma's red")
                at, l1t = fixed_room(size), fixed
            if at is None and L.V2:
                print("V2: level-1 pieces left: %s; fixed bank free %d, runs %s" % (
                    sorted((art_size(t) for t in tl if art_size(t) <= size), reverse=True),
                    sum(1 for x in fixed.used if not x), runs_of(fixed, 16)[:10]))
            if at is None:
                rest = sum(art_size(t) for t in tl if art_size(t) <= size)
                runs, run = [], None
                for a_ in range(l1b.base, l1b.base + BANK + 1):
                    f_ = a_ < l1b.base + BANK and not l1b.used[a_ - l1b.base]
                    if f_ and run is None:
                        run = a_
                    if not f_ and run is not None:
                        runs.append(a_ - run)
                        run = None
                frees = {b: sum(1 for x in banks[b].used if not x) for b in range(7)}
                if os.environ.get("BANKMAP"):          # (BANKMAP=1: the bank's map by what)
                    from collections import Counter as _C
                    for w_, n_ in sorted(_C({w.split(" (")[0].split(" $")[0]: 0 for a__, n__, w in l1b.log}).items()):
                        pass
                    agg = _C()
                    for a__, n__, w in l1b.log:
                        agg[w.split(" (")[0].split(" $")[0][:40]] += n__
                    for w_, n_ in agg.most_common(40):
                        print("  %6d %s" % (n_, w_))
                raise SystemExit("bank %d: no room for a level-1 piece (%d bytes; these and the rest %d; free runs %s; "
                                 "free by bank %s)" % (bk, size, rest, sorted(runs, reverse=True)[:8], frees))
            code_p, sym_p = assemble_at(text, at, far_ph(text))
            l1t.place(at, code_p, "level-1 code")
            placed.append((at, text, len(code_p), [l1t]))
            new = {k: v for k, v in sym_p.items() if k in own_labels(text)}
            far_eq.update(new)
            far_sym.update(new)
            print("level-1 code (bank %d) $%04X + %d bytes (%s)" % (
                bk, at, len(code_p), ", ".join(sorted(new)[:3]) + (" ..." if len(new) > 3 else "")))
    for at, text, n, imgs in placed:           # the second pass: the real labels
        ours = own_labels(text)
        code_p, _ = assemble_at(text, at, dict(main_eq, **{k: v for k, v in far_eq.items() if k not in ours}))
        if len(code_p) != n:
            raise SystemExit("far piece at $%04X changed size between passes" % at)
        for im in imgs:
            im.data[at - im.base:at - im.base + n] = code_p

    pg_sym = {}
    for bk_, x, n_ in keep_pg:
        bk_.release(x, n_, "kept for the per-page copies: given back")
    if L.V2 and textspg:

        def pg_setup(bnum):
            texts = pg_texts(bnum)
            parts = [pt for t in texts for pt in split_long(t, PG_MAXLINES_BY_BANK.get(bnum, PG_MAXLINES), PG_MAKE)]
            own = set().union(*(own_labels(pt) for pt in parts))
            fo = {k: v for k, v in far_eq.items() if k not in own}

            def env(pt):        # (the other parts' labels at a placeholder)
                return dict(main_eq, **fo, **{n: 0xF500 for n in own - own_labels(pt)})
            return texts, parts, fo, env, [len(assemble_at(pt, 0x8000, env(pt))[0]) for pt in parts]
        _, pg_parts, far_out, env1, sizes = pg_setup(-1)
        print("V2: the per-page copies: %d bytes in %d parts (the largest %d)" % (sum(sizes), len(sizes), max(sizes)))
        k_ = 0
        for t in textspg:
            n_ = len(split_long(t, PG_MAXLINES, PG_MAKE))
            print("    %-12s %5d bytes" % (next((ln.split(":")[0] for ln in t if label.match(ln)), "?"), sum(sizes[k_:k_ + n_])))
            k_ += n_
        lo_, hi_ = K.SYS_TABLE - fixed.base, K.SYS_TABLE + len(main_code0) - fixed.base
        print("V2: the fixed bank's free beyond its main block: %d, runs %s" % (
            sum(1 for x in range(BANK) if not fixed.used[x] and not lo_ <= x < hi_),
            [r for r in runs_of(fixed, 16) if r[0] < 2000][:12]))
        for bnum in sorted({L.SCENE_BANK[s] for s in L.PAGE_SCENES}):
            pb = banks[bnum]
            _, pg_parts, far_out, env1, sizes = pg_setup(bnum)
            held = pg_held.get(bnum)            # (its places held before the level-1 pieces)
            if held:
                if [sz for sz, x in held] != sizes:
                    raise SystemExit("V2: bank %d: the held per-page parts changed size" % bnum)
                for sz, x in held:
                    pb.release(x, sz, "held for the per-page copies: given back")
            at_ = {}
            for k in sorted(range(len(pg_parts)), key=lambda k: -sizes[k]):
                x = held[k][1] if held else pgfind(sizes[k], pb, bnum != 4)  # (best fit: the release leaves many short runs; the
                                                 # scene-page code's reserve's tail too, that code placed)
                if x is None and os.environ.get("V2MAP"):
                    from collections import Counter as _C
                    agg = _C()
                    for a__, n__, w in pb.log:
                        agg[re.sub(r"[ (].*", "", w.replace("level 1's ", "level1_").replace("scene ", "scene_")
                                   .replace("system code", "syscode"))[:40]] += n__
                    for w_, n_ in agg.most_common(40):
                        print("    %6d %s" % (n_, w_))
                if x is None:
                    left_ = sorted((sizes[j] for j in range(len(pg_parts)) if j not in at_), reverse=True)
                    raise SystemExit("V2: bank %d: no room for a per-page part (%d bytes; free %d, runs %s; left %d "
                                     "bytes in %d parts %s)" % (bnum, sizes[k], sum(1 for u in pb.used if not u),
                                                                runs_of(pb, 8)[:12], sum(left_), len(left_), left_))
                pb.place(x, bytes(sizes[k]), "the per-page copies (V2)")
                at_[k] = x
            syms = {}
            for k, pt in enumerate(pg_parts):
                syms.update({n: v for n, v in assemble_at(pt, at_[k], env1(pt))[1].items() if n in own_labels(pt)})
            for k, pt in enumerate(pg_parts):
                c_, _ = assemble_at(pt, at_[k], dict(main_eq, **far_out,
                                                     **{n: v for n, v in syms.items() if n not in own_labels(pt)}))
                if len(c_) != sizes[k]:
                    raise SystemExit("V2: a per-page part changed size between passes")
                pb.data[at_[k] - pb.base:at_[k] - pb.base + sizes[k]] = c_
            pg_sym[bnum] = syms
            print("V2: bank %d: the per-page copies placed (%d bytes); %d bytes free" % (
                bnum, sum(sizes), sum(1 for u in pb.used if not u)))
        with open(os.path.splitext(out_path)[0] + ".pgsym", "w") as f:     # (each page's copies' labels)
            for bnum, syms in sorted(pg_sym.items()):
                for n, v in sorted(syms.items(), key=lambda kv: kv[1]):
                    f.write("%d %04X %s\n" % (bnum, v, n))
    if L.V2:
        sp_names_ = {m.group(1) for ln in sp_text for m in [label.match(ln)] if m}
        for sc in L.PAGE_SCENES:
            bk_ = banks[L.SCENE_BANK[sc]]
            sp_code2, _ = assemble_at(sp_text, K.SCENEPAGE_TABLE,
                                      dict(main_eq, **l1_sym, **{k: v for k, v in far_eq.items() if k not in sp_names_},
                                           **pg_sym.get(L.SCENE_BANK[sc], {})))
            if len(sp_code2) != len(sp_code):
                raise SystemExit("the scene pages' code changed size between passes")
            bk_.data[K.SCENEPAGE_TABLE - bk_.base:K.SCENEPAGE_TABLE - bk_.base + len(sp_code2)] = sp_code2
    # (V2: the ending's page, bank 5: bank 4 final, byte for byte)
    if L.V2:
        b4, b5 = banks[L.SCENE_BANK[4]], banks[L.ENDING_BANK]
        b5.data[:] = b4.data
        b5.used[:] = b4.used
        print("V2: the ending's page (bank 5): bank 4's, byte for byte")

    def assemble(extra_eq):
        return assemble_at(main_lines, K.SYS_TABLE, dict(far_eq, **extra_eq))
    code, sym = assemble({})
    if {k: v for k, v in sym.items() if k in main_eq} != main_eq:
        raise SystemExit("system code: the main block moved between passes")
    sym.update(far_sym)
    for name, addr in K.sys_symbols().items():
        if sym[name] != addr:
            raise SystemExit("system jump table: %s at $%04X, the game expects $%04X" % (name, sym[name], addr))
    print("system block $%04X + %d bytes = ends $%04X" % (K.SYS_TABLE, len(code), K.SYS_TABLE + len(code) - 1))
    fixed.place(K.SYS_TABLE, code, "system code and tables")
    # the free-RAM ledger, for port/freecheck.sh
    with open(os.path.splitext(out_path)[0] + ".free", "w") as f:
        for lo, hi, what in L.FREE_RAM:
            f.write("%04X %04X %s\n" % (lo, hi, what))
    # the zero-page map (XEGS byte -> 7800 address), for the probes (beside
    # the cart: work/karateka7800.zp for the usual one)
    with open(os.path.splitext(out_path)[0] + ".zp", "w") as f:
        for z in range(0x100):
            f.write("%02X %04X\n" % (z, zp[z]))
    # the system symbols, for the probes (beside the cart)
    with open(os.path.splitext(out_path)[0] + ".sym", "w") as f:
        # and game addresses the probes key on (bank 15 is shared, so any
        # scene's resolver will do): K_B60F, the flip and frame wait in play
        keys = {"K_B60F": link["scenes"][1]["resolver"].new_addr(0xB60F)}
        for name, addr in sorted(list(sym.items()) + list(keys.items()), key=lambda kv: kv[1]):
            f.write("%04X %s\n" % (addr, name))
    # the game instructions the patch kit's options edit (port/mkkit.py), at
    # their 7800 addresses: {name: [[bank, address], ...]}, one per scene bank.
    # Labels, not the addresses inside routines: bank 15 is reassembled, and
    # only labels map exactly (an address inside a routine gets the region's
    # plain offset, which is wrong wherever instructions changed length)
    sites = {}
    for name, xe, delta, scenes in PATCH_SITES:
        sites[name] = []
        for s in scenes:
            site = [L.SCENE_BANK[s] if xe < 0xA000 or xe >= 0xC000 else 7,
                    link["scenes"][s]["resolver"].new_addr(xe) + delta]
            if site not in sites[name]:          # (scenes sharing a page)
                sites[name].append(site)
            if L.V2 and site[0] == L.SCENE_BANK[4] and [L.ENDING_BANK, site[1]] not in sites[name]:
                sites[name].append([L.ENDING_BANK, site[1]])     # (the ending's page, its copy)
    with open(os.path.splitext(out_path)[0] + ".sites.json", "w") as f:     # (beside the cart: kitopt --cart)
        json.dump(sites, f, indent=1)
    sb = fixed if L.V2 else banks[L.SPARE_BANK]
    so = eq["IMG_SMALLDL"] - sb.base + nmi_stub_off
    for at, v in ((2, sym["NmiGo"]), (18, sym["NmiGo"]), (21, sym["S_NMICOUNT"])):
        sb.data[so + at:so + at + 2] = bytes([v & 0xFF, v >> 8])
    vec = bytes([eq["NMI_STUB"] & 0xFF, eq["NMI_STUB"] >> 8, sym["Reset"] & 0xFF, sym["Reset"] >> 8,
                 sym["Irq"] & 0xFF, sym["Irq"] >> 8])
    fixed.place(0xFFF8, bytes([0xFF, 0xC7]), "region, hash start")
    fixed.place(0xFFFA, vec, "vectors")

    rom = b"".join(bytes(banks[b].data) for b in range(7)) + bytes(fixed.data)
    rom = sign7800.signed(rom)
    # BankSet (FINDINGS "MAME with BankSet"): the image is two halves, the
    # CPU's (the cart as ever, signed alone) and MARIA's, which it reads
    # during its DMA: its window block (the top data and fighters' parts) in
    # all seven window banks, as the CPU may have any of them in, and its
    # fixed bank (the fighters' parts). v1: one 16K of RAM at $4000 both
    # sides share (type $2006, as the openFPGA core and the MAME build do),
    # MARIA's data written there at each scene's load; V2: no RAM ($2002)
    if L.V2:            # (each scene page's window its own; banks 6 and 7 the fixed ones, $4000 and $C000)
        maria = (b"".join(bytes(ts_win.get(b, bytes(BANK))) for b in range(6)) + bytes(mspace.data[:BANK])
                 + bytes(mspace.data[BANK:]))
    else:
        maria = b"".join(bytes(ts_win.get(b, mspace.data[:BANK])) for b in range(7)) + bytes(mspace.data[BANK:])
    hdr = bytearray(128)
    hdr[0] = 3
    hdr[1:10] = b"ATARI7800"
    hdr[17:17 + 22] = b"Karateka (XEGS port)".ljust(22, b"\0")
    hdr[49:53] = (len(rom) + len(maria)).to_bytes(4, "big")
    hdr[53:55] = (0x2002 if L.V2 else 0x2006).to_bytes(2, "big")   # (V2: no cart RAM: bank 6 at $4000)
    hdr[55] = hdr[56] = 1
    hdr[100:128] = b"ACTUAL CART DATA STARTS HERE"
    with open(out_path, "wb") as f:
        f.write(bytes(hdr) + rom + maria)
    used = lambda img: sum(img.used)
    print("fixed bank: %d of %d bytes used; system code $%04X-$%04X"
          % (used(fixed), BANK, K.SYS_TABLE, K.SYS_TABLE + len(code) - 1))
    for b in range(7):
        print("bank %d: %d bytes used" % (b, used(banks[b])))
    # each bank's map, beside the cartridge: what was placed where
    with open(os.path.splitext(out_path)[0] + ".map", "w") as f:
        for img in [fixed] + [banks[b] for b in range(7)]:
            f.write("; %s ($%04X): %d bytes used\n" % (img.name, img.base, used(img)))
            for at, n, what in sorted(img.log):
                f.write("$%04X-$%04X %5d  %s\n" % (at, at + n - 1, n, what))
    print("wrote %s (%d bytes)" % (out_path, len(hdr) + len(rom) + len(maria)))
    return sym


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("-o", "--out", default=os.path.join(HERE, "..", "work", *(("v2",) if L.V2 else ()),
                                                        "karateka7800.a78"))
    ap.add_argument("--v2", action="store_true",
                    help="the V2 build: no cartridge RAM, each scene on its own page (else V2=1)")
    ap.add_argument("--car", help="the original XEGS cartridge (default: KARATEKA_CAR, else "
                    "Karateka.car in the repository, else ../karateka/Karateka.car)")
    ap.add_argument("--snd-offset", type=int, default=None,
                    help="the TIA music's transposition in cents (default SND_OFFSET)")
    args = ap.parse_args()
    global SND_OFFSET
    if args.snd_offset is not None:
        SND_OFFSET = args.snd_offset
    if args.car:
        K.CAR = D.CAR = args.car
    if not os.path.exists(K.CAR):
        raise SystemExit("no original cartridge at %s: give it with --car (README)" % K.CAR)
    os.makedirs(os.path.join(HERE, "..", "work"), exist_ok=True)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    try:
        build(args.out)
    except K.LinkError as e:
        raise SystemExit("link error: %s" % e)


if __name__ == "__main__":
    main()
