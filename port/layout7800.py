#!/usr/bin/env python3
"""
Where every part of XEGS Karateka lives in the 7800 build. See FINDINGS.md,
"The display lists, and the layout that holds", for why.

This module is data plus the address map; port/link7800.py uses it to
assemble each piece of the game at its 7800 address.

The map is by XEGS address and, where scenes differ, by scene:

  sprites  $0480-$06E7  console RAM $1B80   (written: header clipping)
  common   $06E8-$0FFF  scene page  $96E8   (a copy in every scene page)
  engine   $1000-$1202  cart RAM    $7000   (self-modifying; copied at load)
  scode    $1203-$22FF  scene page  $8203
  engine   $2300-$2FFF  cart RAM    $7300   ($24A5-$24AB differ per scene)
  fb B     $3000-$47FF  cart RAM    $4000
  fb A     $4800-$5FFF  cart RAM    $5800
  sdata    $6000-$7FFF  scene page  $A000
  art      $8000-$9FFF  art bank    $8000
  bank 15  $A000-$BFFF  fixed       $C000   (may grow; nothing points into it)

Every move of a region is a whole number of pages, so an address's low byte
never changes. Exceptions, which carry their own mapping:

  - carve-outs: bytes the game writes inside regions that live in ROM (a
    write to $8000-$BFFF switches banks on the 7800); they get RAM homes;
  - scene-code and arrow sprites: page-aligned copies in the fixed bank,
    for the scenes that draw them (the blit's bank is chosen from its
    source page, and these would collide with the art's pages);
  - zero page: XEGS $00-$3F are the 7800's TIA and MARIA registers.
"""

# ---------------------------------------------------------------- regions
# the engine's first part is read-only (the census: the original writes only
# its save slot $1193-$1196, carved out below), so it lives in the fixed
# bank, freeing cart RAM $7000-$7202 for the framebuffers (FINDINGS
# "display lists by the 7800's rules")
ENGINE1_AT = 0xF200   # a whole-page move: split address constants relocate only their high byte

REGIONS = [   # name, XEGS start, end (exclusive), 7800 start, where
    ("sprites", 0x0480, 0x06E8, 0x1B80, "ram"),
    ("common", 0x06E8, 0x1000, 0x96E8, "page"),
    ("engine1", 0x1000, 0x1203, ENGINE1_AT, "fixed"),   # read-only once loaded: ROM
    ("scode", 0x1203, 0x2300, 0x8203, "page"),
    # engine part 2, by the original's own page-aligned modules (FINDINGS "RAM
    # and fixed ROM: step 4"): $2300 data, $2400 the sound, $2C00 the fills,
    # $2E00 the rest: read-only once their variables are carved to RAM, so in
    # the fixed bank; $2800 the blitters, which rewrite their own operands:
    # cart RAM, at its top, so $7300-$7BFF is one free run (step 5)
    ("engine2d", 0x2300, 0x2400, 0xF800, "fixed"),
    ("engine2a", 0x2400, 0x2800, 0xF900, "fixed"),
    ("engine2", 0x2800, 0x2C00, 0xEE00, "fixed"),   # the blitters (no code in cart RAM: BlSetup)
    ("engine2f", 0x2C00, 0x2E00, 0xF600, "fixed"),   # the fills (their writes carved)
    ("engine2c", 0x2E00, 0x3000, 0xFD00, "fixed"),
    ("fbB", 0x3000, 0x4800, 0x4000, "cram"),
    ("fbA", 0x4800, 0x6000, 0x5800, "cram"),
    ("sdata", 0x6000, 0x8000, 0xA000, "page"),
    ("art", 0x8000, 0xA000, 0x8000, "art"),
    ("bank15", 0xA000, 0xC000, 0xC000, "fixed"),
]

# the ROM by scene (FINDINGS "The ROM by scene: the plan"): V2=1 builds the
# new layout beside today's, into work/v2: no cart RAM (the header without
# the RAM bit: bank 6 fixed at $4000 on each side), the shared code and
# graphics in banks 6 and 7, each scene's on its page, no bank switch in play
import os as _os               # noqa: E402
V2 = bool(_os.environ.get("V2"))
SCENES = (0, 1, 2, 3, 4, 6)
SCENE_BANK = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 6: 1}      # 7800 bank per scene (the vs
                                                        # fight in level 1's: VS_REPLACEMENTS)
ART_BANK = 6
FIXED_BANK = 7

# ------------------------------------------------------------ carve-outs
# bytes the game writes inside ROM-resident regions (census, all runs):
# (XEGS start, end exclusive) -> RAM start; blocks keep their internal layout
# the engine's first part: its save slot ($1169 saves $14/$15 and $03/$04
# there, $117E restores them), written before it is read; not copied at load
# and the game's own data in its framebuffer B (cart RAM otherwise): the
# sound's zero-page swap ($258D's routine: $00-$07 with XE $3000-$3007, each
# frame) and a state save (XE $47F7-$4806, between the buffers: $B9C4 saves,
# $BA1D restores);
# console RAM (FINDINGS "The CPU's data out of cart RAM")
import consoleplan_out as CP                    # noqa: E402
CARVE_ENGINE1 = [(0x1193, 0x1197, 0x184E), (0x3000, 0x3008, CP.GSWAP_AT), (0x47F7, 0x4807, CP.GSAVE_AT)]
# engine part 2's bytes written outside the blitter's module (the census;
# FINDINGS "RAM and fixed ROM: step 4"): the sound's variables ($2409-$2421)
# and $2E09-$2E0D, where $2E00's module keeps the vertical blank's vector
# while it swaps it. Zero in the image, so zeroed at each scene load, as the
# original's copy of the engine did. (Reached only by absolute operands.)
# the display-list builder's copy of a list's description (BuildDllF;
# console RAM after CARVE_ENGINE2, in the free run the census found)
DESCBUF, DESCBUF_N = 0x1A2C, 64
CARVE_ENGINE2 = [(0x2409, 0x2422, 0x1A09), (0x2E09, 0x2E0E, 0x1A22),
                 # the fills' saved $06 and the row multiply's operands
                 (0x2CCC, 0x2CCD, 0x1A27), (0x2DA1, 0x2DA4, 0x1A28)]

CARVE_COMMON = [
    (0x0880, 0x0900, 0x1880),      # the zero-page swap buffer (moved from $1A00
                                   # so page $19 and $1A00-$1A08 hold scene 1's
                                   # death sprites, below)
    (0x0AF6, 0x0AFF, 0x1A80),
    (0x0B26, 0x0B27, 0x1A89),
    (0x0C4C, 0x0C51, 0x1A8A),
    (0x0F09, 0x0F18, 0x1A8F),
]
CARVE_SDATA = {                    # per scene
    # scene 1 also: the player's death sprites in scene code, $1E00 19x4,
    # $1E4E 15x7, $1EB9 12x2, $1ED3 13x4 (drawn by $6C52; no census run died, so
    # it was never traced). Scene code sits at $8203+ in the scene page, the
    # art bank's half of the blit rule, so they are read from a RAM copy the
    # loader makes (FINDINGS, "Scene 1")
    1: [(0x7096, 0x7098, 0x1A9E), (0x1E00, 0x1F09, 0x1900)],
    # scene 0: the same pair, and $6009 (written as the story ends, $740A: in
    # ROM a write there is a bank switch, and the next fetch came from bank 7;
    # the census skipped the story's end; FINDINGS "Story crash"); and
    # scene 1's death sprites, which scene 0's copy of the opening run
    # draws too (the same bytes, $1E00-$1F08)
    0: [(0x7096, 0x7098, 0x1A9E), (0x6009, 0x600A, 0x1AA0), (0x1E00, 0x1F09, 0x1900)],
    4: [(0x76FF, 0x7700, 0x1A9E), (0x7706, 0x7707, 0x1A9F)],
    # scene 6 (Select at the title: the fight at the gate) runs scene 1's
    # code in its own banks, flags at $7096/$7097 included (in ROM a write
    # there is a bank switch), and its death sprites; FINDINGS "Select,
    # scene 6"
    6: [(0x7096, 0x7098, 0x1A9E), (0x1E00, 0x1F09, 0x1900)],
}

# ------------------------------------------- sprites copied to the art bank
# scene-code sprites a scene draws that the fixed bank has no room for: copied
# into the art bank's free space (above its images, $B179-$BFFF), page-aligned,
# and read there because the scene's page map (SP_PAGEMAP, 32 bytes for pages
# $A0-$BF in each scene page) sends the blit to the art bank for those pages;
# the scene must draw nothing of its own from them. (start, end exclusive,
# page delta, scenes)
ART_COPIES = [
    # scene 0's intro cutscene (after the story): Akuma, Mariko, the guard
    # (FINDINGS "Story crash"); clear of its own pages (OWN_SPRITE_PAGES) and
    # of the shared copies at $B7-$BA
    (0x1530, 0x18D8, 0x9800, (0,)),             # $AD30-$B0D7
    (0x1CC4, 0x1DFB, 0x9800, (0,)),             # $B4C4-$B5FA
    # scene 4's finale: Mariko's frame at $1F29 (43x4), in the gap between
    # its fixed-bank copies at $1F00 and $1FD7, where the TIA tables now sit;
    # page $BB, which scene 4 never draws from in its own data (its sprite
    # pages are $60-$6F, $75, $76; FINDINGS "The princess room")
    (0x1F29, 0x1FD7, 0x9C00, (4,)),             # $BB29-$BBD6
    # scene 4's own $16FE-$18A1 (the finale's frames), which differ from
    # scenes 2 and 3's at the same addresses: the shared fixed-bank copy was
    # scene 2's, so the finale drew scene 2's bytes there; pages $BC-$BE,
    # not drawn from in scene 4's data
    (0x16FE, 0x18A2, 0xA600, (4,)),             # $BCFE-$BEA1
]
# bank 15's split pointer tables whose targets are scene code: on the XEGS they
# mean "that address in whichever code bank is loaded", so each scene page gets
# its own copy of the high bytes, relocated for that scene, and bank 15 reads
# that. (high table, low table, entries, the copy's address in every scene page)
SCENE_TABLES = [
    (0xBE5A, 0xBE3F, 27, 0x81C0),     # sprite pointers ($BED6): entries 0-19 the intro
                                      # cutscene's, 20-26 scenes 2-4's
]
SP_PAGEMAP = 0x81A0

# ------------------------------------------- the fighters as objects
# FINDINGS "The fighters as objects: step 3". The parts' slices are copied at
# each flip into cart RAM pages FT_P0-FT_PTOP (a slice's grid line g at page
# FT_PTOP - g), buffer A's from column 0 up, B's from FT_COLS down. Their tables are in
# the small-sprite block's RAM (free in play: FINDINGS "The small-sprite block
# moved to paged ROM"; nothing uses them while the block is in, S_GLYIN):
# - FR_*: the fighters drawn into each buffer (bank 15's $A815), four
#   records: A's player, A's enemy, B's player, B's enemy;
# - ZT_*: each buffer's band zones (16 each, A then B), as the list builder
#   made them: the DLL entry (low byte), the grid cell, the zone's first line
#   in it and its height (ZT_H: bits 4-6 and 0-3; bit 7 BandWrite's), the
#   bitmap row's address;
# - FO_*: each buffer's fighter objects (FT_FON each, A then B): the grid
#   cell, x, palette and width, its data's address (low byte; a part's
#   slices are in MARIA's ROM: FINDINGS "BankSet step 1: the fighters'
#   parts"; Akuma's and the hawk's copied into the slice pages) and its page
#   for the cell's line 0 (FO_HB: after the fighters' tables, below; the
#   scene's load clears the counts before any reads them). One copy of the
#   objects for both buffers (FO_BOFF).
FT_P0, FT_PTOP = 0x73, 0x7A
FT_PAL = 4                         # the black palette (skin, black, white)
FT_FON = 40
# (one copy of the objects for both buffers: B's at FO_BOFF, 0, over A's;
# nothing reads a buffer's objects once the other's are written: FtEmit
# records, sorts and writes a buffer's band lists in one go, FINDINGS "What in
# RAM is redundant")
FO_BOFF = 0
FT_COLS = 240                      # the slice pages' columns for the parts: A's from 0 up, B's
                                   # from 224 down, each to where the other's shown parts begin
AK_COLS = 120                      # (levels 3 and 4: the copied parts' columns below it, Akuma's and
                                   # the hawk's poses pre-cut from it to FT_COLS: akpose7800)
FT_BLKCOL = 240                    # FT_BLKW columns of black ($AA in FT_PAL): the front boxes'
FT_BLKW = 16                       # underlay (an opaque box wider: as several, FgBox)
FG_N = 8                           # front boxes a buffer
# (the CPU's blocks and the list pieces: port/consoleplan_out.py, FINDINGS
# "What in RAM is redundant")
import consoleplan_out as CP                    # noqa: E402
# the front boxes (the band's draws after a picture's fighters: RowBase), in
# page heads of the framebuffer's pages (16 bytes each: a buffer's 8, A's
# then B's): as recorded (FGR_*) and as shown (FG_*), first column, width,
# first and last row; then the counts, each buffer's picture's fighters drawn
# (FT_SEEN), a fighter being drawn (FT_IN)
FG_PAGES = range(0x5B, 0x64)
(FGR_C0, FGR_W, FGR_R0, FGR_R1, FG_C0, FG_W, FG_R0, FG_R1, _fgc) = [p * 256 for p in FG_PAGES]
FGR_N, FG_NS = _fgc, _fgc + 2                  # (the front boxes: gone, FINDINGS "The front boxes gone")
FT_SEEN, FT_IN = CP.FTS_AT, CP.FTS_AT + 2       # (console RAM)
FT_RAM = 0x1B80
_ft = {}
_a = FT_RAM
for _name, _n in (("FR_V", 4), ("FR_20", 4), ("FR_21", 4), ("FR_22", 4), ("FR_50", 4), ("FR_3E", 4),
                  ("FR_36", 4), ("ZT_DLL", 32), ("ZT_CELL", 32), ("ZT_H", 32),
                  ("FO_CELL", FT_FON), ("FO_X", FT_FON),
                  ("FO_PW", FT_FON), ("FO_LO", FT_FON),
                  # the copy's (FtEmit's, never the interrupt's): the source's
                  # bank; a plain part's top row, rows' end, box column; the
                  # upper body's base column and eighths, its pose; the head's
                  # image, nudge, column and eighths
                  ("FT_SRCB", 1), ("FP_ROW", 1), ("FP_END", 1), ("FP_COL", 1), ("FP_BCOL", 1),
                  ("FP_BSUB", 1), ("FP_UY", 1), ("FP_HI", 1), ("FP_HV", 1), ("FP_HCOL", 1),
                  ("FP_HSUB", 1),
                  # a band zone's fighter objects' columns, first to past the last
                  # (BandWrite: only the front boxes over them matter), and
                  # the cell they are for (its zones share them)
                  ("FB_XMIN", 1), ("FB_XMAX", 1), ("FB_CELL", 1),
                  # each record's box as last shown (FtBoxOf: its objects'
                  # columns, first to past the last, and cells' rows), and
                  # each buffer's records changed since its last emit (an
                  # earlier picture's fighter erased, or the buffer cleared
                  # or copied: FINDINGS "The fighters as objects: step 4")
                  ("FR_C0", 8), ("FR_C1", 8), ("FR_R0", 8), ("FR_R1", 8), ("FT_DIRTY", 2),
                  # each buffer's parts as last copied (FtEmit: a buffer's
                  # player's upper body, enemy's upper body, player's lower
                  # body, enemy's lower body): their key (pose; upper: type
                  # | $36 << 7), first column, whole (none left out for
                  # room); the columns each buffer's shown parts take
                  # (FT_USE); a part's first object (PO_ST: 4 parts, Akuma,
                  # the star, the end; then each upper body's first after its
                  # pose mask, drawn before the lower body as bank 15 does); the emit's part, its index into those, its key,
                  # whether its slices are already in place (FP_NOCP), a
                  # slice's column, FtPlace's step and the buffer's first
                  # object, the part's record (FtObj grows its box)
                  ("RU_K1", 8), ("RU_K2", 8), ("RU_OK", 12), ("FT_USE", 2), ("PO_ST", 9),
                  ("FP_PART", 1), ("FP_CLS", 1), ("FP_K1", 1), ("FP_K2", 1), ("FP_NOCP", 1),
                  ("FP_SCOL", 1), ("FP_PI", 1), ("FP_OBASE", 1), ("FP_REC", 1),
                  # a record's bytes read (FtRead5: a slice's or a tall
                  # image's), an object's page for its cell's line 0 (FO_HB);
                  # a cell's 160B objects (BandWrite: each one's 5-byte
                  # header and the next's), the write mode its list is in
                  ("FP_RB", 5), ("FP_T", 1), ("FB_NB", 1), ("FB_MB", 1),
                  # each record's place at its buffer's last emit ($22, $50;
                  # LS_22 $FF: none): an emit as the last is skipped (FtSame)
                  ("LS_22", 4), ("LS_50", 4)):

    _ft[_name] = _a
    _a += _n
# then, with the same life (FtEmit's: unread while the small-sprite block is
# in, S_GLYIN), the fighter objects sorted by grid cell, the black ones first
# in a cell (FtSort: their indexes), each cell's first, count and next
# place (FS_I, FC_*, BANDX_A), one sort for both buffers (B's at FS_BOFF 0),
# and each object's page for its cell's line 0 (FO_HB, one copy)
FS_I, FS_BOFF = _a, 0
FC_START, FC_N, FC_CUR = FS_I + FT_FON, FS_I + FT_FON + 10, FS_I + FT_FON + 20
FS_END = FS_I + FT_FON + 30
FO_HB = FS_END + 10
# (V2) the columns a buffer's fighter objects show in, from FT_ML to before
# 40 - FT_MRI (0 and 0: the screen's), but where the picture's black fills
# after the fighters cover the screen's edges (the rooms' doorways: FINDINGS
# "Fighters behind the doorways"); zero when cleared, as the load does
FT_ML, FT_MRI = FO_HB + FT_FON, FO_HB + FT_FON + 2
# (V2) where L1PartW's last entry in the zone's list ended (L1Zone clears it):
# a part's entry the same as the one just before it is dropped (FINDINGS
# "Akuma's red": two shapes at one place with one window there). (+5 free:
# the guard's colour latches were here, unused since "Run 10")
L1_LW = FO_HB + FT_FON + 4
# level 2's band palette 3 (FINDINGS "The hawk's blue"): the NMI number of
# the band's colour DLI (0 none) and the band's grey, as ColTail saw them
# last frame; the NMI writes the grey at once, ahead of the game's handler
P3E_N, P3E_G = FO_HB + FT_FON + 6, FO_HB + FT_FON + 7
# (V2) a front instance's columns + 64 (first, past the last) for L1FrHit
L1FH_A, L1FH_B = FO_HB + FT_FON + 8, FO_HB + FT_FON + 9
# (V2) a list held for the main program to build (FINDINGS "The switch
# frames: built outside the NMI"): the frames it has been held (0 none), the
# colour scheme ($0F0C) of the picture on screen, and the one the game's
# vertical blank set for the held list
HOLD_N, HOLD_SCH, HOLD_NEW = FO_HB + FT_FON + 10, FO_HB + FT_FON + 11, FO_HB + FT_FON + 12
# (V2) the tiles' palette 5 below the split as the band's set last made it
# (ColTail), for the band's DLI to write at once (FINDINGS "Run 10")
L1PE = FO_HB + FT_FON + 13
# (V2) the NMI number of the game's DLI handler running (NmiDliRun)
DLI_NUM = FO_HB + FT_FON + 16
# (V2) FtObjV's right mask, a byte more for a shifted object
MRI_E = FO_HB + FT_FON + 17
# (V2) each buffer's view's half pixel ($50 bit 0; at 2 x the buffer: L1Flip)
L1_VP = FO_HB + FT_FON + 18
# (V2) the status bar's set (FINDINGS "The flickering arrows"): the NMI
# number of its DLI as ColTail saw it this frame (0 none), the one latched
# at the vertical blank from last frame's (NmiVbi), and palette 1's three
# colours, for the NMI to write at once, ahead of a music DLI's handler
P6E_N, P6E_A, P6E = FO_HB + FT_FON + 21, FO_HB + FT_FON + 22, FO_HB + FT_FON + 23
_a = FO_HB + FT_FON + 26
assert _a <= 0x1DF6, "the fighters' tables run past the small-sprite block's RAM"
# Akuma's blits as each buffer last drew them (FINDINGS "Akuma as objects"):
# in console RAM that play leaves alone ($1AA1-$1B7F: written only at boot;
# the census's reads at $1B00 are indexed reads' page-crossing dummies).
# AK_V as FR_V; AK_N blits, at most AK_MAX a buffer (buffer * AK_MAX + n):
# the image and its bank, column ($05), top row ($06 - 35), shift ($10),
# flags (bit 7 mirrored, 6 its column the right byte's, 5 a mask: AND);
# the source pages captured (AK_PG0-AK_PG1: the scene's data, $A0-$BF);
# whether each buffer's last emit showed him (LS_AK); his routine's address
# (AK_VEC: SysAkW)
AK_MAX = 10
_a = 0x1AA1
for _name, _n in (("AK_V", 2), ("AK_N", 2), ("AK_LO", 2 * AK_MAX), ("AK_HI", 2 * AK_MAX),
                  ("AK_BK", 2 * AK_MAX), ("AK_COL", 2 * AK_MAX), ("AK_ROW", 2 * AK_MAX),
                  ("AK_SH", 2 * AK_MAX), ("AK_FL", 2 * AK_MAX), ("AK_PG0", 1), ("AK_PG1", 1),
                  ("LS_AK", 2), ("AK_VEC", 2),
                  # each buffer's hit star (bank 15's $B503/$B54D: FINDINGS
                  # "The hit stars as objects"): 2 drawn this picture, 1 an
                  # earlier one's (as FR_V), 0 none; the big (0) or small
                  # (1) one; its top row ($06 - 35), column ($05) and shift
                  # ($10); whether its buffer's last emit showed one. Its box
                  # is FR_C0/C1/R0/R1 4 + buffer, its part FP_CLS 8 + buffer
                  ("SR_V", 2), ("SR_IMG", 2), ("SR_ROW", 2), ("SR_COL", 2), ("SR_SUB", 2),
                  ("LS_STAR", 2),
                  # a pair of Akuma's (a mask and the sprite drawn over it,
                  # FtEmitAk) copied as one: whether one is (FP_PAIR), the
                  # sprite's rows and the mask's, the row in them, the merge's
                  # scratch, $14/$15 as they were (the mask's pointer)
                  ("FP_PAIR", 1), ("FP_SROWS", 1), ("FP_MROWS", 1), ("FP_RI", 1),
                  ("PT_S", 1), ("PT_M", 1), ("PT_T", 1), ("FP_Z14", 2),
                  # each buffer's captures start afresh at its next capture
                  # (set at its emit: Akuma's and the hawk's share the list)
                  ("AK_FR", 2)):
    _ft[_name] = _a
    _a += _n
assert _a <= 0x1B80, "Akuma's tables run into the fighters'"
# (V2) level 2's portcullis as one image a buffer (FINDINGS "The portcullis as
# one image"): its record in Akuma's capture arrays' last entries, which scene
# 2 never fills (FtEmitAk runs only with AK_V): PC_V drawn this picture 2, an
# earlier one's 1, none 0; PC_ROW the last bar row the game drew (80: only the
# lintel's line); PC_TIP its bottom piece (PC_TIPS_LO's, $FF none yet)
_ft["PC_V"] = _ft["AK_HI"] + 2 * AK_MAX - 2
_ft["PC_ROW"] = _ft["AK_BK"] + 2 * AK_MAX - 2
_ft["PC_TIP"] = _ft["AK_COL"] + 2 * AK_MAX - 2
# (and the column and shift the game drew it at, $05 and $10: it scrolls in
# with its gate; at 32 always, it stood still till the gate was in place:
# FINDINGS "The hardware test")
_ft["PC_COL"] = _ft["AK_LO"] + 2 * AK_MAX - 2
_ft["PC_SH"] = _ft["AK_SH"] + 2 * AK_MAX - 2
PC_TIPS_LO = (0x00, 0x16, 0x2C, 0x4C, 0x7B, 0xB4)      # (the game's $A0xx: rows 81-89, 90-97, 98-104,
_ft["PC_NTIP"] = len(PC_TIPS_LO)                         # 105-112, 113-119, 120-125)
FT_TABLES = _ft
FT_TABLES.update({"FGR_C0": FGR_C0, "FGR_W": FGR_W, "FGR_R0": FGR_R0, "FGR_R1": FGR_R1, "FG_C0": FG_C0,
                  "FG_W": FG_W, "FG_R0": FG_R0, "FG_R1": FG_R1, "FGR_N": FGR_N, "FG_NS": FG_NS,
                  "FT_SEEN": FT_SEEN, "FT_IN": FT_IN, "FO_HB": FO_HB, "FT_ML": FT_ML, "FT_MRI": FT_MRI,
                  "L1_LW": L1_LW, "P3E_N": P3E_N, "P3E_G": P3E_G, "L1FH_A": L1FH_A, "L1FH_B": L1FH_B,
                  "HOLD_N": HOLD_N, "HOLD_SCH": HOLD_SCH, "HOLD_NEW": HOLD_NEW,
                  "L1PE": L1PE, "DLI_NUM": DLI_NUM, "MRI_E": MRI_E, "L1_VP": L1_VP,
                  "P6E_N": P6E_N, "P6E_A": P6E_A, "P6E": P6E})

# ------------------------------------------- the shared sprite copies
# scene-code sprite runs (read as blit sources in scenes 0, 2, 3, 4; identical
# bytes wherever two scenes read the same address) and the health arrows.
# (XEGS start, end exclusive, page delta, scenes.) A copy below $C000 is in
# the art bank, read there through the scenes' page maps as ART_COPIES are;
# they were in the fixed bank until its room went to the engine (FINDINGS
# "RAM and fixed ROM: step 2"). Bank 15's pointers at $B826-$B82A (the
# scenery objects 6-10: $1200, $12C8, $14BE, $18BF, $18D0) are the same in
# every scene, so those copies are mapped in every scene that draws them
# (0, 2, 3, 4).
SPRITE_COPIES = [
    (0x1200, 0x1524, 0xA500, (0, 2, 3, 4)),     # $B700-$BA23: from $1200, since
                                                # scene 3's floor stripes (9x22)
                                                # start with their header in the
                                                # engine's last three bytes
    (0x1530, 0x15B3, 0x9F00, (3, 4)),           # $B430-$B4B2
    (0x1600, 0x16FE, 0x9D00, (2, 3, 4)),        # $B300-$B3FD
    (0x16FE, 0x18A2, 0x9A00, (2, 3)),           # $B0FE-$B2A1: scene 4 has its
                                                # own sprites here (the finale's;
                                                # ART_COPIES)
    (0x18BF, 0x18D8, 0xA200, (0, 2, 3, 4)),     # $BABF-$BAD7
    (0x1C80, 0x1CFA, 0x8600, (4,)),             # $A280-$A2F9 (to $1CF9: the
                                                # 5x2 frame at $1CEE, scene 4)
    (0x1F00, 0x1F29, 0x8300, (4,)),             # $A200-$A228
    (0x1FD7, 0x1FFD, 0x9300, (4,)),             # $B2D7-$B2FC
    # ($2193-$2275, the title's first copyright line: no longer blitted (the
    # title is objects, whose set-up reads it from scene 0's page))
    # (the health arrows' copy in the fixed bank, $FF12-$FF24: none since the
    # status bar's arrows are objects from MARIA's ROM; no run reads it:
    # FINDINGS "The fixed bank: room")
    # the mirrored blitter's byte table, $2BC0-$2CBF: it runs from the
    # blitters' last page (cart RAM) into the fills' first (ROM), so it is
    # read whole from a copy in the fixed bank
    (0x2BC0, 0x2CC0, 0xF500 - 0x2BC0, SCENES),  # $F500-$F5FF (fixed)
]
# each scene's own sprites in pages $A0-$BF (its scene data, XEGS $6000-
# $7FFF): its images drawn in the runs, those the table walk found, and
# Akuma's finale pieces (work/analysis/assets; FINDINGS "The sprite tables
# walked"), and the port's own blits (probes/p7800-blitpages.lua: scene 0's
# demo fight, which the original's runs never reach). A page map may not send
# these to the art bank (the build checks).
OWN_SPRITE_PAGES = {
    0: tuple(range(0xA1, 0xAD)) + (0xB2, 0xB3, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF),
    1: tuple(range(0xA0, 0xAD)) + (0xB4, 0xB5, 0xB6, 0xB7, 0xBE, 0xBF),
    2: tuple(range(0xA0, 0xAE)) + (0xBE, 0xBF),
    3: tuple(range(0xA0, 0xA8)) + (0xAA, 0xAB, 0xAC, 0xAD, 0xBE, 0xBF),
    4: (0xA0, 0xA1) + tuple(range(0xA3, 0xB1)) + (0xB5, 0xB6),
    6: (0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xAC, 0xB4, 0xB5, 0xB6, 0xB7, 0xBF),
}

# ------------------------------------------------------------- zero page
FREE_ZP = [0x49, 0x63, 0x64, 0x6E, 0x73, 0x74, 0x7E, 0x8E, 0x9B, 0x9C, 0x9D,
           0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xCB,
           0xCC, 0xCD, 0xCE, 0xCF, 0xD1, 0xD3, 0xD4, 0xD5, 0xD6, 0xDA, 0xE9,
           0xEC, 0xF3, 0xF4, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF]
# used only by bank 15, so moving them to absolute RAM grows only bank 15
MOVERS = [0x26, 0x27, 0x28, 0x2B, 0x2C, 0x32, 0x3A, 0x3C, 0x3D,
          0x6C, 0x6D, 0x7A, 0x7C, 0x7D, 0x8A, 0x9E, 0x9F, 0xA6]
MOVER_BASE = 0x1800
PINNED = {0x00: 0xC6, 0x01: 0xC7, 0x02: 0xC8, 0x03: 0xC9, 0x04: 0xCA,
          0x05: 0xCB, 0x06: 0xCC, 0x07: 0xCD,           # overlapping pointers
          0x0A: 0xCE, 0x0B: 0xCF, 0x0D: 0xD3, 0x0E: 0xD4,
          0x14: 0xD5, 0x15: 0xD6}
# zero-page bytes the game never references still need a home for the
# swap and clear loops: a scratch block
ZP_SCRATCH = 0x1820


def zero_page_map(usage):
    """XEGS zero page -> 7800 address, for all 256 bytes.

    usage: {xegs zp: reference count}, to give the busiest bytes the zero-page
    slots. $40-$FF stay where they are unless they are movers."""
    out = {}
    for i, z in enumerate(MOVERS):
        out[z] = MOVER_BASE + i
    out.update(PINNED)
    slots = [z for z in FREE_ZP if z not in PINNED.values()] + [z for z in MOVERS if z >= 0x40]
    need = [z for z in range(0x40) if z not in out and usage.get(z)]
    need.sort(key=lambda z: -usage.get(z, 0))
    if len(need) > len(slots):
        raise SystemExit("zero page: %d bytes for %d slots" % (len(need), len(slots)))
    for z, slot in zip(need, sorted(slots)):
        out[z] = slot
    scratch = ZP_SCRATCH
    taken = set(out.values())
    for z in range(0x100):
        if z not in out:
            # unused by the game: itself, unless that address now holds another
            # byte (the swap and clear loops walk all of $00-$7F)
            out[z] = z if (z >= 0x40 and z not in taken) else None
        if out[z] is None:
            out[z] = scratch
            scratch += 1
    return out


# ------------------------------------------------- system RAM and shadows
SYS = 0x1E00                      # system variables (console RAM)
SYSVARS = [                       # name, size
    ("S_BANK", 1),                # the bank now in the window
    ("S_SCENEBANK", 1),           # the scene page
    ("S_NMICOUNT", 1),            # interrupts so far this frame
    ("S_NMIVBI", 1),              # the count at which the VBI zone fires
    ("S_DLIST", 2),               # DLISTL/H as the game wrote them
    ("S_DLIST_A", 2),             # the XEGS display list the A-list was built for
    ("S_DLIST_B", 2),
    ("S_NMIEN", 1), ("S_NMIRES", 1), ("S_DMACTL", 1), ("S_CONSOL", 1),
    ("S_PORTA", 1), ("S_LATCH", 1), ("S_SINK", 1), ("S_VCOUNT", 1),
    ("S_CTRL", 1),                # MARIA CTRL for the list being shown
    ("S_TMP", 4),
    ("S_POKEY", 16),              # POKEY register shadow ($D200-$D20F)
    ("S_VDSLST", 2), ("S_VIMIRQ", 2), ("S_VVBLKI", 2),
    ("S_SDMCTL", 1), ("S_SDLST", 2), ("S_SSKCTL", 1), ("S_COLDST", 1),
    ("S_OS033B", 1),
    ("S_FRAMES", 1),              # vertical-blank stand-ins so far
    ("S_VBI_A", 1), ("S_VBI_B", 1),   # NMI count at which each list's VBI fires
    ("S_DLIDX", 1),               # table index of the list being built or shown
    ("S_ROWBASE", 2), ("S_ROWP", 2), ("S_DLI1", 1), ("S_FLAG", 1),
    ("S_LINES", 1), ("S_NDLI", 1), ("S_KIND", 1), ("S_COUNT", 1), ("S_ARG", 1),
    ("S_SND04", 1),               # $04 kept across the sound starter
    ("S_BUSY", 1),                # Frame is running (it must not re-enter)
    ("S_PEND", 1),                # a list chosen but not yet shown
    ("S_PDPPL", 1), ("S_PDPPH", 1), ("S_PCTRL", 1), ("S_PVBI", 1),
    ("S_BLPC", 1),                 # the band lists' pieces: $00 level 1's, $10 levels 2-4's, $FF none
    ("S_INVBI", 1),               # the vertical blank is running (it never nests)
    ("S_DLSP", 2), ("S_SLOT", 1), ("S_H", 1), ("S_HASDLI", 1), ("S_RROW", 1), ("S_MRG", 1),
    ("S_CPL", 1), ("S_CPH", 1),   # the zone builder, the rows, the column routine
    ("S_BTMP", 2),                # the list builder's scratch
    ("S_INDLI", 1),               # the game's DLI handler is running
    # the top rows' sky (FINDINGS "The top rows as objects"): the list being
    # built has it (S_TSKY); each buffer's list's two port DLIs, by their NMI
    # number in the frame (sky on, sky off; 0 none); the shown list's, and as
    # applied; the sky's colour (the top band's colour 2)
    ("S_TSKY", 1), ("S_PDA1", 1), ("S_PDA2", 1), ("S_PDB1", 1), ("S_PDB2", 1),
    ("S_PPD1", 1), ("S_PPD2", 1), ("S_NMIPD1", 1), ("S_NMIPD2", 1), ("S_SKY", 1),
    ("S_VS", 1), ("S_SCID", 1),   # the vs fight in level 1's page: $80 in it; the identity byte
    ("S_TRAL", 1),                # TopCapture: $80, a mirrored blit's column its right byte's
    ("S_VWAIT", 1),
    ("S_STUBBK", 1),              # StubIn/StubOut: the caller's bank
    ("S_DLBUF", 1), ("S_DLLO", 1), ("S_DLHI", 1),   # BuildDllF: the list's DLT entries               # the NMI: the game's flip wait ($0AF6) as its vertical blank began
    ("S_TSET", 1),                # the top pieces' set loaded: 0 the scene's, 1 its other (TOP_ALT)
    ("S_PBLANK", 1), ("S_SHOWBLANK", 1),   # the blank list is chosen / on screen
    ("S_RSWCHA", 1), ("S_RSWCHB", 1),     # RIOT, read in vertical blank
    ("S_BTX", 1),                 # BlitBank keeps the blitter's X here
    ("S_SN", 2), ("S_SSTEP", 1), ("S_SCH", 1), ("S_SVOL", 1), ("S_SF", 1),   # TiaSound's scratch
    ("S_VBIPEND", 1),             # a vertical blank waits for it to end
    ("S_DLIPEND", 1),             # a DLI waits for the one running to end
    ("S_CHOSEN", 3),              # the list Frame last chose, and its DMA bit
    # the status bar's cache (FINDINGS "The health arrows, drawn only when
    # they change"): per buffer (A, B) the player's and the foe's health last
    # drawn there ($FF: unknown; foe $FE: none drawn), this picture's state
    ("S_STP", 2), ("S_STF", 2),
    ("S_STR", 1), ("S_STX", 1), ("S_STL", 1), ("S_STW", 1),   # StBuild's scratch (arrows
                                  # left, x, the object's first byte and width)
    # the column routine's (FINDINGS "The tiny sprites are columns"): the
    # loop's limit, X and Y, the template piece's rows, bytes a row, and
    # per byte what to keep of the screen (K) and what to put there (T),
    # 8 a row; the pieces' first row and the rows this one draws
    ("S_CLIM", 1), ("S_CX", 1), ("S_CY", 1), ("S_CNONE", 1),
    ("S_CH", 1), ("S_CNB", 1), ("S_CJ", 1), ("S_CHH", 1), ("S_CR", 1),
    ("S_CT", 16), ("S_CK", 16),
    # the fast fill's (FINDINGS "The fast fill"): the value, the row stride
    # (40, or 80 for the pattern's passes), rows, whole blocks left,
    # scratch, and the pattern's start
    ("S_FVAL", 1), ("S_FSTRIDE", 1), ("S_FCOUNT", 1), ("S_FK", 1), ("S_FT", 1),
    ("S_FP0", 2),
    # the story and title as MARIA objects (FINDINGS "The story as letter
    # objects", "The title as objects"): the story on; what each buffer holds
    # of the title (1 the logo, 2 the copyright); the buffers whose bitmaps
    # hold the objects' data (shown blank). Their scratch: OBJVARS
    ("S_STORY", 1), ("S_TITLEA", 1), ("S_TITLEB", 1), ("S_OBLANK", 1),
    ("S_CLIPROW", 48),            # RowBase's scratch row: a draw that starts
                                  # below the bottom lands here (col + width
                                  # <= 40, plus the edge byte and blitter B's -1)
    ("S_BDLP", 2),                # the next band zone's list (BAND_A, BAND_B)
    ("S_GLYIN", 1),               # the small-sprite block is in RAM (TextInF)
    # the fighters as objects (FINDINGS "The fighters as objects: step 3"):
    # each buffer's band zones (ZT) and fighter objects (FO), counts; the copy's
    # scratch
    ("S_ZTN", 2), ("S_FON", 2),
    ("S_FX", 1), ("S_FMIR", 1), ("S_FW", 1), ("S_FN", 1), ("S_FL0", 1),
    ("S_FCOL", 1), ("S_FLIM", 1), ("S_FBOX", 1), ("S_FSW", 1), ("S_FCNT", 1),
    ("S_FJ", 1), ("S_FTK", 1), ("S_FBUF", 1), ("S_FZ", 1), ("S_FPAL", 1), ("S_FB0", 1),
    ("S_FOV", 1), ("S_FZR", 1), ("S_FSUB", 1),
]


# the story's and title's scratch, used only while they are on: page $43's
# first 16 bytes (framebuffer pages keep offsets 0-15 out of the buffers,
# $4000-$420F hold the XEGS gaps, and the full clear starts at offset 16)
OBJVARS_AT = CP.OBJV_AT                         # (console RAM: FINDINGS "Console RAM laid out scene by scene")
OBJVARS = [
    ("S_STORYT", 2),              # the scroll step (0-377)
    ("S_STORYF", 1),              # the frame of the last step
    ("S_SPAT", 2),                # the next patched copy
    ("S_SCLS", 1), ("S_SA", 1), ("S_SJ", 1), ("S_SMAX", 1), ("S_SCOL", 1), ("S_SSH", 1),
    ("S_SGB", 1),                 # the patch's base page (the slot's or canvas's top row)
    ("S_SLN", 1), ("S_STOP", 1), ("S_SBOT", 1),  # the text's lines, its first and last rows
    ("S_CTOP", 1),                # the level-1 column routine's first piece's line (FgCol)
]


def sysvars():
    names = [n for n, _ in SYSVARS + OBJVARS + TOPVARS]
    dup = sorted({n for n in names if names.count(n) > 1})
    assert not dup, "system variables defined twice: %s" % dup
    out, a = {}, SYS
    for name, n in SYSVARS:
        out[name] = a
        a += n
    assert a <= 0x1F00, "system variables run into the mode-8 rows"
    a = OBJVARS_AT
    for name, n in OBJVARS:
        out[name] = a
        a += n
    assert a <= OBJVARS_AT + 16, "the objects' scratch runs past page $43's first 16 bytes"
    a = TOPVARS_AT
    for name, n in TOPVARS:
        out[name] = a
        a += n
    assert a <= 0x2040, "the top rows' scratch runs past $203F"
    assert out["S_TB1"] == out["S_TB0"] + 1 and out["S_TF0"] == out["S_TB0"] + 2   # (TopLoad indexes them)
    return out


# the top rows' scratch (FINDINGS "The top rows as objects"): console RAM
# after the status lists (once in the free-RAM ledger)
TOPVARS_AT = 0x2018
TOPVARS = [
    ("S_CUTK", 1),                # RowBase: the rows a draw loses above the cut
    ("S_TT", 1),                  # the scene's first top piece (the TOP_ tables)
    ("S_TBUF", 1),                # a buffer's first list entry: 0 A, 16 B
    ("S_TN", 1),                  # how many
    ("S_TROW", 1),                # a draw's top row
    ("S_TMIR", 1),                # $80: mirrored (the blit $2B8B)
    ("S_TI", 1),                  # a piece's index
    ("S_TL", 2),                  # its left pixel (signed)
    ("S_TX0", 1), ("S_TX1", 1),   # a box: its pixels on screen
    ("S_TR0", 1), ("S_TR1", 1),   # and rows
    ("S_TB0", 1), ("S_TB1", 1),   # a fill's pixels
    ("S_TF0", 1), ("S_TF1", 1),   # and rows
    ("S_TDLP", 2),                # the next top-zone display list slot
    ("S_TJ", 1), ("S_TK", 1),     # loop counters
    ("S_TW", 1),                  # a width
    ("S_TTMP", 2),
    ("S_EBUF", 1), ("S_EK", 1), ("S_EW", 1), ("S_EI", 1), ("S_EJ", 1),   # TopEmit's own (it
    ("S_ETMP", 2),                # runs in the NMI, maybe inside TopCapture)
    ("S_ER", 1),                  # TopRefresh's slot count (the NMI's too)
    ("S_TZ", 5),                  # TopLoad: a piece's data column in each zone
    ("S_TCOL", 1),                # inside a captured column (ColA, ColC: its pieces not captured)
    ("S_TCOLK", 1),               # TopColumnF: the column's kind
    ("S_TCH", 1),                 # TopLoad: a column's image rows left before it repeats
]


# the story as letter objects: while it scrolls the framebuffers are idle, so
# its glyphs, line templates and patched copies live in their pages, at page
# offsets 16 and up (0-15 hold the XEGS gaps). Glyph row r at page
# STORY_G - r (rows 0-13: a zone reads line L at page high + OFFSET);
# templates two a page (offsets 16, 128), 22 lines; patched copies (two a
# page) STORY_PATN pages a buffer: A's from STORY_PATA, B's from STORY_PATB,
# pages the title's canvases (TITLE_PLO-TITLE_G) leave free. A picture needs
# up to 10: the partial top and bottom lines, and two at each of the four
# DLI rows in the text (FINDINGS "The story's patched lists overran"). The
# story: strings STORY_FIRST on, STORY_N of them, 14 rows apart;
# the entering string's top at buffer row STORY_ROW0 at step 0; the text
# shows on rows STORY_TOP-STORY_BOT (the original clears the rest)
STORY_G, STORY_GTAB = 0x5F, 0x5110
STORY_TPL, STORY_PATA, STORY_PATB, STORY_PATN = 0x60, 0x6B, 0x42, 5
STORY_FIRST, STORY_N, STORY_PITCH = 4, 22, 14
STORY_ROW0, STORY_TOP, STORY_BOT = 140, 2, 140
# the title as objects: two canvases, a canvas's top row at page TITLE_G and
# each row one lower (the logo's rows, then the copyright's; the pages below
# to TITLE_PLO); the templates and the objects' columns and widths in page
# TITLE_TPL (the build checks the canvases' rows fit)
TITLE_G, TITLE_TPL = 0x66, 0x67     # (clear of the status strips, pages $40-$46)
# the status bar as objects (FINDINGS "The status bar as objects"): each
# buffer's status zone's display list (18 objects and the end: every count
# up to 27 a bar, or any that fit on screen); console RAM no one writes after
# the BIOS (probes/p7800-ramwrites.lua); both lists' first objects in page $1F
# (each 57 bytes: StBuild's 11 objects of 5 at most and the end; B's right
# after A's, both in one page)
STATUS_DLA, STATUS_DLB = 0x1F80, 0x1F80 + 57
assert (STATUS_DLB + 57 - 1) >> 8 == STATUS_DLA >> 8
# the arrows' strips (a block of 4, 5 bytes, each bar's): in the heads of
# framebuffer pages ST_HI (the bottom row) to ST_HI + 6, outside the buffers
# (offsets 0-15; nothing else writes those pages' heads: probes/p7800-
# pageheads.lua), the player's at ST_PLO, the foe's at ST_FLO
ST_HI, ST_PLO, ST_FLO = 0x44, 0, 5

# the top rows as objects (FINDINGS "The top rows as objects"): the pieces
# the game draws above FB_TOP, per level (scenes 1 and 6 share level 1's):
# (the image's XEGS address, its top row, mirrored), as the logs saw them
# (probes/p7800-toplog.lua; mirrored: drawn through $2B8B). Their rows above
# the cut, per TOP_ZONE zone, are loaded at the scene's load into columns of
# pages TOP_PBASE-14 to TOP_PBASE (row r's bytes at TOP_PBASE - r % 15), from
# byte TOP_DLO; level 1's converted for its sky background (colour 2
# transparent, colour 0 an opaque black in palette TOP_PAL1)
_T1 = [(0x60A8, 42, 0), (0x6146, 33, 0), (0x61B4, 19, 0), (0x6242, 11, 0), (0x6274, 3, 0)]
# the level-1 column routine's columns above the cut, one piece each (the
# image repeated from its top to the cut; "col"): the posts and pillars
_T1 += [(0x6684, 37, m, "col") for m in (0, 1)] + [(0x6703, 37, m, "col") for m in (0, 1)]
_T1 += [(0x685F, 55, m, "col") for m in (0, 1)] + [(0x6000, 64, 0, "col")]
# the mountain, and a piece of the gate
_T1 += [(0x6948, 46, 0) + (("fuji",) if V2 else ()), (0x6976, 57, 0) + (("fuji",) if V2 else ()),
        (0x6038, 54, 0)]                # (V2: Mt Fuji redrawn, fuji7800)
# "the end" (the game over, levels 1-4: the common text routine $07BF, row
# 56; its glyphs use all four colours, so not converted for the sky: "raw")
# (V2: row 55, the game's $2EAE row $5B made $5A: at 56 its glyphs' tenth row
# is row 65, the band's, which V2 draws only from tiles: the letters' feet
# were lost; FINDINGS "Recording 02")
_END = [(a, 55 if V2 else 56, 0, "raw") for a in (0x04C2, 0x04D8, 0x0522, 0x0588, 0x0614)]
_T1 += _END
# the door frames at the screen's edges (scenes 0, 2-4: bank 15 $B866-$B980,
# from the art bank), plain and mirrored
_DF = [(a, top, m) for a, top in ((0x9600, 48), (0x964A, 60), (0x96CE, 60), (0x9980, 56)) for m in (0, 1)]
_T1 += [(src, top, m) for src, top in ((0x6707, 1), (0x6763, 37), (0x67D1, 26), (0x682B, 19), (0x6857, 13))
        for m in (0, 1)]
# level 3: the door frames, its tall columns (92 x 10, at 13 places as the
# rooms scroll), "the end". The door frames and the column move with the
# scroll's shift and the game's erases of their old places aren't on whole
# bytes: each one object, a draw replacing its earlier places ("one")
_T3 = [p + ("one",) for p in _DF + [(0x6000, 51, 0)]] + _END
# level 2 (FINDINGS "Step 1: level 2's wall"): the window wall, rows 45-66,
# drawn opaque over the background as the blitter's store mode does:
# - its colour bands by four fills; the one at row 46 ($AA) stands for the
#   whole wall over its columns ("fill": TOP_FILLP "wall2"), the others erase;
# - its joints ($64D8, plain and mirrored), moved by painting the wall over
#   the old ones ($64F0: "erase", a fill over its rectangle) and drawing them
#   further on;
# - the distant mountain through it ($6592, $65B8), the gate building
#   ($6602) and its edge ($6546), the door frames, "the end"
_T2 = [(0x6274, 18, 0), (0x6602, 22, 0, "one"), (0x6546, 45, 0, "one")]
_T2 += [("wall2", 45, 0, "fill")]
_T2 += ([(0x64F0, 45, m, "erase") for m in (0, 1)] + [(0x64D8, 45, m) for m in (0, 1)] if not V2 else
        # (V2: the joints one entry a buffer, 32 pixels apart, expanded as the
        # zones' lists are written; their erases nothing: FINDINGS "Level 2's
        # windows: the joints as one entry")
        [(0x64D8, 45, m, "joint") for m in (0, 1)])      # (their erases no piece: ignored)
_T2 += [(0x6592, 46, 0, "one") + (("fuji",) if V2 else ()), (0x65B8, 58, 0, "one") + (("fuji",) if V2 else ())]
_T2 += [p + ("one",) for p in _DF] + _END
# scene 0 (the attract loop; off while the story or title is up: StoryInit,
# TitleMark): its demo fight on level 1's scenery, by scene 0's own copy of
# level 1's code (the torii, the mountain, the posts; on the sky, converted
# as level 1's). Its posts are drawn by the game's own column loops (the
# port's column routine is in level 1's pages only), so each is a chained
# column: its first piece's blit captures the whole column, and the pieces
# below match nothing ("chain"). Its cutscenes' door frames: the other set.
_T0 = [(0x6707, 1, 0), (0x6763, 37, 0), (0x67D1, 26, 0), (0x682B, 19, 0), (0x6857, 13, 0)]
_T0 += [(0x6684, 37, m, "chain") for m in (0, 1)] + [(0x6703, 37, m, "chain") for m in (0, 1)]
_T0 += [(0x685F, 55, m, "chain") for m in (0, 1)]
_T0 += [(0x6948, 46, 0) + (("fuji",) if V2 else ()), (0x6976, 57, 0) + (("fuji",) if V2 else ())]
TOP_PIECES = {0: _T0, 1: _T1, 6: _T1, 2: _T2, 3: _T3, 4: _DF + _END}
# a scene's other set of pieces: never on screen with its first set, so in
# the same data columns, loaded in place of the first when one is drawn (and
# back): level 1's page shows the door frames in Akuma's cutscene (FINDINGS
# "Step 1: scene 0, and level 1's cutscene"); as drawn, on the cutscene's
# black ("raw": not level 1's sky conversion)
TOP_ALT = {0: [p + ("one", "raw") for p in _DF], 1: [p + ("one", "raw") for p in _DF]}
# True: level 1's sky (colour 2 transparent over it, 0 an opaque black);
# "opaque": every piece opaque, as the blitter's store draws it (black moved
# to a colour the piece doesn't use); False: as drawn
TOP_CONVERT = {0: True, 1: True, 6: True, 2: "opaque", 3: False, 4: False}
# the fill pieces: a fill the scene makes (its first row, its colour byte)
# stands for this piece over the fill's columns, in entries of w bytes; its
# rows' bytes as shown, in palette pal
TOP_FILLP = {"wall2": {"match": (46, 0xAA), "w": 20, "pal": 3,
                       "rows": [0xFF] + [0xAA] * 9 + [0x55] * 2 + [0xFF] + [0xAA] * 9}}
TOP_PBASE, TOP_DLO, TOP_DEND = 0x4E, 16, 255    # data columns: bytes 16-254 of pages $40-$4E
                                                # ($40FF is the XEGS buffers' gap)
# BankSet (FINDINGS "BankSet step 1: the top pieces"): the sets' data, converted
# by the build, in MARIA's half: in groups of 15 pages from TOP_MPAGE in the
# window block every MARIA-side window bank holds (the CPU's bank switching
# then doesn't matter), a set's columns packed beside others' in its group
TOP_MPAGE = 0x40 if V2 else 0x80   # (V2: in MARIA's fixed bank 6 at $4000, every scene's: the window's
                                   # banks hold each scene's own: FINDINGS "The ROM by scene: the plan")
# the sets' groups (FINDINGS "The title and the opening scroll in bank 0's
# MARIA copy"): bank 0 (scenes 0 and 4's page) is never in the window during
# levels 1-3, so the groups holding only their sets (TS_PAGES) are free in
# bank 0's MARIA copy for the title's and the story's data; scenes 0, 3 and 4
# share the first group
TOP_GROUPS = ((0, 3, 4), (1, 6), (2,))
TS_PAGES = range(TOP_MPAGE + 15, TOP_MPAGE + 3 * 15)          # (groups of TOP_ZONE pages)
if V2:                  # (the text in its scene's own window: banks 0 and 4, its first 30 pages;
    TS_PAGES = range(0x80, 0x80 + 30)   # the tiles' characters at their CHB + $40 above them)
TOP_PAL1 = 2                                    # the converted pieces' palette
TOP_PAL2 = 3                                    # the opaque pieces' second: colour 1 black
# each buffer's top-zone list slots: 60 bytes each, four a page (offsets
# $10, $4C, $88, $C4), ten a buffer, end to end from $4F10 (B's from $5188):
# a pass uses at most ten, a slot at most 52 bytes of objects (FINDINGS "The
# fighters as objects: step 1, the top rows' slots"); pages $54-$56 freed
# in gameplay (the title's canvases use them: not in FREE_RAM)
TOPDL_SIZE, TOPDL_N = 60, 10
TOPDL_A = 0x4F10
def _slot_after(a, n):
    for _ in range(n):
        a = a + TOPDL_SIZE if (a & 0xFF) + TOPDL_SIZE <= 0xFF - TOPDL_SIZE + 1 else (a & 0xFF00) + 0x110
    return a
TOPDL_B = _slot_after(TOPDL_A, TOPDL_N)
TOPDL_AEND, TOPDL_BEND = TOPDL_B, _slot_after(TOPDL_B, TOPDL_N)
TOPDL_LAST = 0x10 + 3 * TOPDL_SIZE                 # a page's last slot
assert (TOPDL_A, TOPDL_B, TOPDL_BEND) == (0x4F10, 0x5188, 0x5410), (hex(TOPDL_B), hex(TOPDL_BEND))
# each buffer's pieces, in draw order (A's entries 0-15, B's 16-31): the
# piece, its left pixel's low byte, the first byte kept and the end; then
# each buffer's count and its top's background colour (0-3)
# (in page $57, which the buffers left; not console RAM $2040-$20FF or
# $2140-$21FF: those are zero page and the stack, mirrored: FINDINGS "The
# RAM census: correction")
TOPLI, TOPLX, TOPLK0, TOPLK1 = CP.TOPLI_AT, CP.TOPLX_AT, CP.TOPLK0_AT, CP.TOPLK1_AT   # (2 x TOPL_MAX each:
TOPLN, TOPLBG, TOPL_MAX = CP.TOPLS_AT, CP.TOPLS_AT + 2, CP.TOPL_MAX                  # console RAM now)
# each buffer's pieces changed since its top zones' lists were last written
# (they are written again as it is next shown: TopRefresh); a slot holds
# its zone's first row and height at offsets TOPDL_ARG, TOPDL_ARG + 1 (after
# its longest list: TopEmit stops at TOPDL_ARG - 2, 14 objects)
TOPLD, TOPDL_ARG = CP.TOPLS_AT + 4, TOPDL_SIZE - 2
# the top zones' lists are written straight into console RAM's top pieces
# (TopEmit counts, then writes: no slot copies, FINDINGS "The top lists
# written in place"); a slot keeps only its zone (row, height) by ordinal,
# and TopEmit's pass state: in slot A's old place for now (CPU data in cart
# RAM, to move with the TP_* group)
TOPZ_ARG, TOPZ_H = CP.TOPZA_AT, CP.TOPZH_AT     # (console RAM now)
TP_EK, TP_PASS, TP_T0, TP_T1, TP_T2 = [CP.TOPZT_AT + i for i in range(5)]
assert TOPL_MAX == 28                           # (the user's clean run reaches 25)
S_TPB = 0x1F18                                  # the top set's data's top page in MARIA's ROM
                                                # (TopEmit's high bytes; TopLoad's row was here)
# the title's and story's character zones (FINDINGS "The title and the
# opening scroll in bank 0's MARIA copy"), in TopLoad's old row ($1F19-$1F27):
# the next NMI's entry in the tables (the NMI takes it first thing), the
# shown list's table base + 1 (0: none), the chosen one's (Apply), each
# buffer's (A 1, B TS_CHB + 1: its list is the title's or story's), the
# builder's state (its zones' CHBASE so far, DLIs, the description's place,
# a story line's list, its row in the slot and its line, the zone's list,
# the NMI's scratch)
TSVARS = {"S_TSFREE": 0x1F19, "S_NMICHT": 0x1F1A, "S_PCHT": 0x1F1B, "S_CHONA": 0x1F1C, "S_CHONB": 0x1F1D,
          "S_TSCUR": 0x1F1E, "S_TSN": 0x1F1F, "S_TSD": 0x1F20, "S_TSLL": 0x1F22, "S_TSQ": 0x1F23,
          "S_TSL": 0x1F24, "S_TSDL": 0x1F25, "S_TSPT": 0x1F27}
# each DLI's CHBASE for its zone (0: none), A's from TS_CHTV + 1, B's from
# TS_CHTV + TS_CHB + 1 (the entry after the last 0), in console RAM no one
# writes ($2100-$213F: FINDINGS "Console RAM: what must stay"); whether it is
# ours alone (not the game's), from TS_CHTP + 1 / + TS_CHB + 1, in DLS_A's tail
# (its row lists end well before); the title's and story's lists: A's in
# DLS_A below that, B's in DLS_B, each from offset $20
TS_CHB, TS_DLIS = 31, 30
TS_CHTV, TS_CHTP = 0x2100, 0x24C0
TS_DLA, TS_DLB, TS_DLAEND, TS_DLBEND = 0x2420, 0x2520, 0x24C0, 0x2600   # (above the row lists: about
                                                                    # 30 bytes; the story's last picture lasts
                                                                    # while the next list is built over them)
assert TS_CHTV + 2 * TS_CHB + 1 <= 0x2140 and TS_CHTP + 2 * TS_CHB + 2 <= 0x2500
# the sky's switch lines, opaque so the background may change anywhere in
# them: 20 bytes of colour 2 (TOPSKYROW), shown twice across the line, in the
# bitmap's palette (the top's last row: sky) or the pieces' (the blank line
# before the top: black); the latter's list at TOPBLACKDL
TOPSKYROW, TOPBLACKDL = 0x1F28, 0x1F3C
# the text lines' pointers (the story's or the ending's), copied at set-up:
# in page $40, outside the framebuffers (in page $51 they were copied before
# the set-up blanks the buffers, and showed for a frame as a line of dots:
# FINDINGS "The story's patched lists overran")
STORY_PLO, STORY_PHI = 0x4010, 0x4030
END_N, END_BOT = 10, 152          # the ending: ten strings, the text rows to the bottom
assert STORY_PLO + max(STORY_N, END_N) <= STORY_PHI and STORY_PHI + max(STORY_N, END_N) <= 0x4050
STORY_PACE = 9                    # frames the step waits for; a step takes one fewer on
                                  # average (8.0, as the bitmap port; MAME's XEGS 7)

DLL_A = 0x2200                    # display list lists, one per framebuffer (a page each:
DLL_B = 0x2300                    # MARIA reads one across at most one page boundary)
DLS_A = 0x2400                    # the display lists of each buffer's row zones
DLS_B = 0x2500
SMALLDL_AT = 0x2780               # the empty and mode-8 row lists and the blank DLL

# the framebuffers for MARIA's multi-line zones: pages FB_PBOT-FB_PTOP, six
# 40-byte rows a page at bytes 16-255; buffer A columns 0-2, B 3-5, each
# column FB_BAND rows, the row below one page lower (FINDINGS "display lists
# by the 7800's rules"). The buffers hold the rows above the status bar
# (FB_ROWS; the bar is objects: FINDINGS "The status bar's rows given
# back") and below the top rows (FB_TOP; what draws there is objects:
# FINDINGS "The top rows as objects"): rows FB_TOP to FB_ROWS-1, so a column
# is 34 rows (its last, row 146, unused) and pages $40-$4E are free of them
FB_TOP = 65
TOP_ZONE = 15                       # the top rows' zones: rows 0-14, 15-29, 30-44, 45-59, 60-64
TOP_NZ = (FB_TOP + TOP_ZONE - 1) // TOP_ZONE
FB_ROWS = 146
FB_BAND = (FB_ROWS - FB_TOP + 2) // 3
# the buffer rows' zones: at most BAND_ZH rows, on a BAND_ZH grid within each
# column (the actors' parts are cut on it: their data in RAM needs that many
# consecutive pages; FINDINGS "The actors' RAM working set")
BAND_ZH = 8
assert BAND_ZH & (BAND_ZH - 1) == 0
# the rows on that grid: the grid zones meeting the actors' rows (79-128:
# up to 134); below, zones of up to 16 as before. Only while the title is
# off (gameplay, the attract demo): their lists are then packed in pages
# $54-$56 (the title's canvases' otherwise), a buffer's in its own half (A
# BAND_A to BAND_AEND, B BAND_B to BAND_BEND, 360 bytes each, a list never
# across a page's end: on at the next page's offset 16), leaving room for
# the fighters' objects (FINDINGS "The fighters as objects: step 1"); at
# most BAND_N a buffer. With the title up, the rows' zones are as before: at
# most 16, lists in DLS_A/B.
BAND_ZEND = 134
BAND_N = 16
BAND_A, BAND_AEND = 0x5410, 0x5588
BAND_B, BAND_BEND = 0x5588, 0x5700
def _band_pack(a, sizes):
    """where lists of these sizes go from a (each on at offset 16 of the next
    page when it would cross a page's end): the address after them"""
    for n in sizes:
        if (a & 0xFF) + n > 0x100:
            a = (a & 0xFF00) + 0x110
        a += n
    return a
assert _band_pack(BAND_A, [10] * BAND_N) <= BAND_AEND and _band_pack(BAND_B, [10] * BAND_N) <= BAND_BEND
# each band zone's own 16 bytes (a buffer's zone k: BAND_HEADS[16 * buffer +
# k]): a list of at most 16 (the bitmap's two objects and one more) goes
# there, the longer ones in the buffer's area, so the zones still to come
# need no room kept there (FINDINGS "The fighters as objects: step 4"). The
# page heads of $4B-$5A (A) and $64-$72 (B), B's last in page $7B's tail
BAND_HEADS = ([p * 256 for p in range(0x4B, 0x5B)] + [p * 256 for p in range(0x64, 0x73)]
              + [0x7BF0])
assert len(BAND_HEADS) == 2 * BAND_N
# and when a buffer's area is full, page $7B's tails after the fighters'
# sort (A BANDX_A to BANDX_AEND, B BANDX_B to BANDX_BEND, before B's last
# head), S_BX the next place's low byte
# (the sort's cells' next places first; the old band writer's overflow,
# S_BLPC $FF, scene 5's, after them)
# (the sort shared: the cells' next places only, 10; scene 5's old band
# writer, S_BLPC $FF, has no overflow room now: it drops objects instead)
BANDX_A, BANDX_AEND = FS_END, FS_END + 10
BANDX_B, BANDX_BEND = BANDX_A, BANDX_AEND
S_BX = 0x1F78
# bank 15's fighter-box erase ($A780 the enemy's, $A78C the player's: a
# black fill over the box, then the floor under it; FINDINGS "The
# fighter-box fills dropped"): S_ERS, set at its entry, is $C0 when its box
# holds nothing of the bitmap's, so its fills paint nothing ($80
# otherwise). FT_DRW, a record each, says how the fighter was last drawn in
# that buffer: 1 as objects, 2 into the bitmap (the glyphs in, or the
# scene's own enemy, Akuma), 0 not at all (set by FRec, taken by the erase;
# FR_V can't say, since the other fighter's erase wipes a record its box
# overlaps). The player's erase paints unless 1 (its 0 is the level's own
# figures: the opening pose, the death fall); the enemy's only at 2 (its 0
# is no enemy, parked off-screen, whose erase bank 15 clamps to columns
# 0-10). S_NOFILL is set around a fill that paints nothing, which keeps its
# bookkeeping (RowBase's FgRec: an earlier picture's fighter there is
# erased)
S_NOFILL, S_ERS, FT_DRW = 0x1F79, 0x1F7A, 0x1F7B
FB_PTOP = 0x72
FB_PBOT = FB_PTOP - FB_BAND + 1
XE_ROW0 = (0x4808, 0x3010)          # the XEGS buffers' row 0: A, B (40 bytes a row)
# the XEGS bytes around the rows (not shown) that the game uses: $47F8-$4807
# holds the end of the 16-byte record at $47F7 (bank 15's copies at $BA73,
# $BA7E; its first byte is B's last row's last byte), $3000-$300F is written
# at load; the rest is spare. Their 7800 homes: $3000 as before (the
# cartridge's POKEY), the others in pages' free first 16 bytes, $47F8 at
# $4100 so the record stays in one piece after $40FF (B row 152 byte 39)
XE_GAPS = [(0x3000, 0x3010, 0x4000), (0x47F7, 0x4808, 0x40FF), (0x5FF0, 0x6000, 0x4200)]


def fb_row(buf, r):
    """buffer 0 (A) or 1 (B), row r (FB_TOP to FB_ROWS-1): its first byte"""
    assert FB_TOP <= r < FB_TOP + 3 * FB_BAND, r
    r -= FB_TOP
    col = 3 * buf + r // FB_BAND
    return (FB_PTOP - r % FB_BAND) * 256 + 16 + 40 * col


# RAM no one uses (the ledger of what the conversion gives back): nothing but
# the boot's clear writes it. The build writes it to work/karateka7800.free
# and port/freecheck.sh proves it, every scene (FINDINGS "The status bar's
# rows given back"). (lo, hi inclusive, what it was)
FREE_RAM = [
] + [(p * 256 + (10 if ST_HI <= p <= ST_HI + 6 else 0), p * 256 + 15,
      "page $%02X's head: outside the buffers" % p)
     for p in range(ST_HI, FB_PTOP + 1) if p not in FG_PAGES and p * 256 not in BAND_HEADS]


def fb_home(a):
    """an XEGS framebuffer address ($3000-$5FFF): its 7800 home"""
    for buf in (0, 1):
        off = a - XE_ROW0[buf]
        if FB_TOP * 40 <= off < FB_ROWS * 40:
            return fb_row(buf, off // 40) + off % 40
    for lo, hi, new in XE_GAPS:
        if lo <= a < hi:
            return new + (a - lo)
    raise ValueError("$%04X: not in a framebuffer" % a)

# hardware and OS symbols, as xesource.py names them -> 7800 address
def hw_map(sv):
    return {
        "COLPF0": 0x25, "COLPF1": 0x26, "COLPF2": 0x27, "COLPF3": 0x28,   # palette 1
        "COLBK": 0x20, "TRIG0": 0x0C, "TRIG1": 0x0D, "WSYNC": 0x24,
        "CONSOL": sv["S_CONSOL"], "HITCLR": sv["S_SINK"], "HPOSP0": sv["S_SINK"],
        "ST_P": sv["S_STP"], "ST_F": sv["S_STF"],   # the status bar's arrows shown, per buffer
        "ST_PS": (ST_HI + 6) * 256 + ST_PLO,   # its strips' top row
        "FL_VAL": sv["S_FVAL"], "FL_STRIDE": sv["S_FSTRIDE"], "FL_COUNT": sv["S_FCOUNT"],   # the fast fill
        "PORTA": sv["S_PORTA"], "PORTB": sv["S_SINK"], "PACTL": sv["S_SINK"], "PBCTL": sv["S_SINK"],
        "DMACTL": sv["S_DMACTL"], "CHACTL": sv["S_SINK"], "DLISTL": sv["S_DLIST"],
        "DLISTH": sv["S_DLIST"] + 1, "HSCROL": sv["S_SINK"], "VSCROL": sv["S_SINK"],
        "PMBASE": sv["S_SINK"], "CHBASE": sv["S_SINK"], "VCOUNT": sv["S_VCOUNT"],
        "NMIEN": sv["S_NMIEN"], "NMIRES": sv["S_NMIRES"], "BANKSEL": sv["S_SINK"],
        "AUDF1": sv["S_POKEY"] + 0, "AUDC1": sv["S_POKEY"] + 1, "AUDF2": sv["S_POKEY"] + 2,
        "AUDC2": sv["S_POKEY"] + 3, "AUDF3": sv["S_POKEY"] + 4, "AUDC3": sv["S_POKEY"] + 5,
        "AUDF4": sv["S_POKEY"] + 6, "AUDC4": sv["S_POKEY"] + 7, "AUDCTL": sv["S_POKEY"] + 8,
        "KBCODE": sv["S_POKEY"] + 9, "RANDOM": sv["S_POKEY"] + 10,
        "IRQEN": sv["S_POKEY"] + 14, "SKCTL": sv["S_POKEY"] + 15,
        # OS page shadows the game uses
        "V_0200": sv["S_VDSLST"], "V_0201": sv["S_VDSLST"] + 1,
        "V_0216": sv["S_VIMIRQ"], "V_0217": sv["S_VIMIRQ"] + 1,
        "V_0222": sv["S_VVBLKI"], "V_0223": sv["S_VVBLKI"] + 1,
        "V_022F": sv["S_SDMCTL"], "V_0230": sv["S_SDLST"], "V_0231": sv["S_SDLST"] + 1,
        "V_0232": sv["S_SSKCTL"], "V_0244": sv["S_COLDST"], "V_033B": sv["S_OS033B"],
        # the clear loop's self-modified store: operand high byte set at run time
        "OS_FF00": 0xFF00,
    }


# ----------------------------------------------------------- replacements
# XEGS address -> (end exclusive, lines). Outside bank 15 a replacement must
# assemble to exactly the bytes it replaces (the linker checks).
NOP = "    NOP"


def pad(lines, size_so_far, size):
    return lines + [NOP] * (size - size_so_far)


def unrolled(src_base, dst_base, n, x_after, src_sym, dst_sym):
    """A 16-byte record copy, unrolled so the bytes can live anywhere."""
    out = []
    for i in range(n):
        out.append("    LDA %s" % src_sym(src_base + i))
        out.append("    STA %s" % dst_sym(dst_base + i))
    out.append("    LDX #$%02X" % x_after)
    return out


def common_at(a):
    """an XEGS common-bank address: its 7800 address"""
    return [new + (a - lo) for name, lo, hi, new, where in REGIONS if name == "common"][0]


def fitted(lines, end):
    """lines padded with NOPs up to the XEGS address end (the common bank
    keeps its size; the assembler fills to the label's 7800 address)"""
    lab = "Pad_%04X" % end
    return lines + [lab + ":", "    .res $%04X-%s,$EA" % (common_at(end), lab)]


# the status bar's arrows: the game's two images ($0B12 the player's, drawn
# mirrored; $0B1C the foe's: height, width, the rows), and each bar's strip
# row by row: 4 arrows (20 pixels, 5 bytes), as the game draws them ($0B3E
# at x = 5i, $0B98 at 155 - 5i)
ARROW_IMG = {0x0B12: [0x07, 0x01, 0x01, 0x05, 0x15, 0x55, 0x15, 0x05, 0x01],
             0x0B1C: [0x07, 0x01, 0x02, 0x0A, 0x2A, 0xAA, 0x2A, 0x0A, 0x02]}


def arrow_rows(img, mirror, xs):
    im = ARROW_IMG[img]
    rows = [bytearray(40) for _ in range(im[0])]
    for x in xs:
        for r in range(im[0]):
            v = im[2 + r]
            if mirror:
                v = ((v & 3) << 6) | ((v >> 2 & 3) << 4) | ((v >> 4 & 3) << 2) | (v >> 6 & 3)
            for k in range(4):
                px = (v >> (6 - 2 * k)) & 3
                if px and 0 <= x + k < 160:
                    rows[r][(x + k) // 4] |= px << (6 - 2 * ((x + k) % 4))
    return rows


ST_PATP = [b for r in arrow_rows(0x0B12, True, [5 * i for i in range(28)]) for b in r[0:5]]
ST_PATF = [b for r in arrow_rows(0x0B1C, False, [155 - 5 * i for i in range(28)]) for b in r[35:40]]
assert len(ST_PATP) == len(ST_PATF) == 35 and ST_PATP[0]     # (StInit's "built" test)


def bytes_lines(label, bs):
    return [label + ":"] + ["    .byte " + ",".join("$%02X" % b for b in bs[i:i + 16])
                            for i in range(0, len(bs), 16)]


# the status bar as objects: the game's clear ($0B27) and its arrows ($0B3E
# the player's, $B6 of them; $0B98 the foe's, $B7), every picture into the
# buffer being drawn, now only set how many arrows that buffer shows (none
# below 3 in buffer B: they blink, as on the XEGS) and build its list
# (ScStBuild, sys7800.asm). The player's warning below 3 stays the game's.
# Their images ($0B12-$0B25) and the flag's old home ($0B26, carved) are
# free for the helpers. The strips (ST_HI) are made at the first clear
# (StInit; RAM is clear at boot, and the player's strip's first byte is not)
# from their rows (ST_PAT: each row the player's 5 bytes and the foe's 5),
# kept in the story scroll's old code ($0806, dead since the story became
# objects).
STATUS_CODE = {
    0x0806: (0x0862, fitted(bytes_lines("ST_PAT", [b for r in range(7) for b in
                                                    ST_PATP[5 * r:5 * r + 5] + ST_PATF[5 * r:5 * r + 5]]), 0x0862)),
    0x0B12: (0x0B27, fitted([
        "StIdx:",                       # X = the buffer being drawn: 0 A, 1 B
        "    LDX #$00", "    LDA Z_07", "    CMP #$20", "    BNE StIdxA", "    INX",
        "StIdxA:", "    RTS"], 0x0B27)),
    0x0B27: (0x0B3E, fitted([
        "    JSR StIdx", "    LDA #$00", "    STA ST_P,X", "    STA ST_F,X",
        "    JMP ScStBuild"], 0x0B3E)),
    0x0B3E: (0x0B98, fitted([
        "    LDA Z_B6", "    BEQ StPSet", "    CMP #$03", "    BCS StPOk",
        "    LDA L_0B26", "    BMI StPSet", "    LDA #$15", "    JSR L_2422",
        "    LDA #$FF", "    BNE StPFlag",
        "StPOk:", "    LDA #$00",
        "StPFlag:", "    STA L_0B26",
        "StPSet:", "    JSR StIdx", "    LDA Z_B6", "    JSR StShown", "    STA ST_P,X",
        "    JMP ScStBuild",
        "StShown:",                     # A = health: the arrows buffer X shows
        "    CMP #$03", "    BCS StShownA", "    CPX #$01", "    BNE StShownA",
        "    LDA #$00",
        "StShownA:", "    RTS"], 0x0B98)),
    0x0B98: (0x0BDD, fitted([
        "    JSR StIdx", "    LDA Z_B7", "    JSR StShown", "    STA ST_F,X",
        "    JMP ScStBuild"], 0x0BDD)),        # (the strips: in MARIA's ROM, build7800)
}


def replacements(scene=None):
    z = lambda a: "Z_%02X" % a
    v47 = lambda a: "V_47F7+%d" % (a - 0x47F7) if a != 0x47F7 else "V_47F7"
    r = {
        # zero-page swap and clear: same-size jumps to system routines
        0x1159: (0x1169, pad(["    JMP SysZpSwap"], 3, 16)),
        # the fighters as objects (FINDINGS "The fighters as objects: step 3"):
        # bank 15's fighter drawing ($A815: LDX $20, LDA $50) records the
        # fighter for the buffer being drawn first; the colour routine's end
        # ($1155: DEY, BPL $1148, RTS) also sets the fighters' black palette
        # (FT_PAL: the band's skin and white, and black)
        0xA815: (0xA819, pad(["    JSR SysFRec"], 3, 4)),
        # the fighter-box erase (both fighters'): its entries decide
        # (S_ERS), its black fill and the floor's fill or pattern under it
        # paint nothing when an object was all there was (S_NOFILL)
        0xA780: (0xA783, ["    JMP SysErE"]),
        0xA78C: (0xA78F, ["    JMP SysErP"]),
        0xA7C2: (0xA7C5, ["    JSR SysNoFill"]),
        0xA7F1: (0xA7F4, ["    JMP SysNoPat"]),
        0xA800: (0xA803, ["    JMP SysNoPat"]),
        0xA809: (0xA80C, ["    JMP SysNoPat"]),
        0xA812: (0xA815, ["    JMP SysNoFill"]),
        # ... and a fighter's last part (its torso, a tail call: the player's,
        # the enemy's) marks its drawing done: the band's draws after are in
        # front of it (the front boxes)
        0xA8B4: (0xA8B7, ["    JMP SysFtEnd"]),
        # step 4: the lower-body masks the level's code draws first are part
        # of the merged lower body (FINDINGS "The fighters as objects: step 4")
        0xAA71: (0xAA74, ["    JMP SysMaskP"]),
        # ... and the common flip ($0862, the levels' through $0803) does what
        # $B60F's does: the top rows' refresh and the fighters' objects
        0x0862: (0x0865, ["    JSR SysFlip0"]),
        0xAA54: (0xAA57, ["    JMP SysMaskE"]),
        # the hit stars (FINDINGS "The hit stars as objects"): each one's mask
        # blit records it instead, its sprite blit (the tail call) is dropped
        0xB533: (0xB536, ["    JSR SysStarM"]),
        0xB549: (0xB54C, ["    JMP SysStarS"]),
        0xB580: (0xB583, ["    JSR SysStarM"]),
        0xB592: (0xB595, ["    JMP SysStarS"]),
        0xA940: (0xA943, ["    JMP SysFtEnd2"]),
        0x1155: (0x1159, pad(["    JMP SysColTail"], 3, 4)),
        0x2E59: (0x2E69, pad(["    JMP SysZpSwap"], 3, 16)),
        0x0EAA: (0x0EB4, pad(["    JMP SysZpClear"], 3, 10)),
        # the text routine's start (LDY #$00, STY $0F): its glyphs, the
        # small-sprite block, brought into RAM first (no longer copied at
        # boot; FINDINGS "The small-sprite block moved to paged ROM")
        0x0780: (0x0784, pad(["    JSR SysTextIn"], 3, 4)),
        # the loader: $2F5A loads everything, $2F66 the scene's banks
        0x2F5A: (0x2F66, pad(["    JSR SysLoadCommon"], 3, 12)),
        0x2F66: (0x2F8A, pad(["    JMP SysLoadScene"], 3, 36)),
        # wait for scanline 200
        0x2F8A: (0x2F91, pad(["    JSR SysWaitLine200"], 3, 7)),
        # the sound's frame-wait counters ($0AFC/$0AFD; the vs fight's
        # $0AF9/$0AFA): its module is in ROM now, so the vs fight's two
        # operands are chosen by S_VS in the system, not patched
        0x24A4: (0x24A7, ["    JSR SysFwLo"]),
        0x24AA: (0x24AD, ["    JSR SysFwHi"]),
        # $0FFB (vertical-blank step 8) starts in the common bank and runs on
        # into the engine at $1000; on the 7800 those are apart
        0x0FFB: (0x1000, pad(["    JMP SysCommonTail"], 3, 5)),
        # bug fix: the sound-effect starter uses $04/$05 as its own pointer and
        # leaves $04 (the blitter's source high byte) at $F8; a text blit that
        # only reloads $03 then draws OS code as dots. SysSound keeps $04.
        0x2422: (0x2426, pad(["    JMP SysSound"], 3, 4)),
        # the game picks its display list here ($0F87 ... $0F93 STA DLISTH / RTS):
        # pick the MARIA list at the same moment
        0x0F93: (0x0F97, pad(["    JMP SysSetDlist"], 3, 4)),
        # the flip and frame wait in play: the picture is done, so the buffer
        # drawn has its top zones' lists written again here, in the main
        # program (same size: bank 15 has no room to grow; SysTopFlip does
        # $B60F's LDA $0AFE, and its RTS leaves the flags; FINDINGS "The top
        # rows' flicker")
        0xB60F: (0xB612, ["    JSR SysTopFlip"]),
        # the stick
        0x0990: (0x0993, ["    JSR SysReadStick"]),
        0xAD09: (0xAD0C, ["    JSR SysReadStick"]),
        # blit bank switching: pick the bank from the source pointer, and
        # give the scene page back when the pointer is restored
        0x29DC: (0x29E0, pad(["    JSR SysBlitBank"], 3, 4)),
        # the blitters in ROM (the BankSet spec: no code in cart RAM): each
        # one's set-up patched its combine opcode (by the mode $0F: AND, ORA
        # or none) and its shift routine's JSR operands (by the shift $10);
        # now BlSetup keeps those in BL_MODE and BL_SHV, the first byte's
        # shift is BlSh (JMP (BL_SHV)) and each inner loop one of three
        # (;;; FAR (BlRom))
        0x289B: (0x28CA, pad(["    JSR SysBlSetup", "    JMP L_28CA"], 6, 47)),     # the normal blitter
        0x28F9: (0x28FC, ["    JSR SysBlSh"]),
        0x291A: (0x292E, pad(["    JMP SysBlLoopN"], 3, 20)),
        0x2A6D: (0x2A9C, pad(["    JSR SysBlSetup", "    JMP L_2A9C"], 6, 47)),     # the mirrored one
        0x2AD9: (0x2ADC, ["    JSR SysBlSh"]),
        0x2AFA: (0x2B19, pad(["    JMP SysBlLoopM"], 3, 31)),
        0x29FF: (0x2A04, pad(["    JMP SysBlitDone"], 3, 5)),
        # level 1 without the blitter (FINDINGS "Level 1 without the blitter:
        # steps 3 and 4"): the fills' clip, the rectangle's and the pattern's;
        # in level 1 the fill an eraser of instances and not drawn, else the
        # clip as before
        0x2CCD: (0x2CD0, ["    JSR SysL1Fill"]),
        0x2D03: (0x2D06, ["    JSR SysL1Pat"]),
        # bug fix: the row address ($2D46: row = Y - 35, times 40, plus the
        # buffer) has no bottom check, and the blitters and fills go on 40
        # bytes a row for as many rows as asked. A sprite partly below the
        # screen (the cutscene) wrote past the buffer: on the XEGS into scene
        # data RAM at $6000 (or, from buffer B, into the top of buffer A), on
        # the 7800 into the engine at $7000, which then crashed. SysRowBase
        # stops every draw at the last row (FINDINGS "Drawing below the
        # screen").
        # (the first 16 bytes, up to the multiply; the buffer base after it
        # stays the game's)
        0x2D46: (0x2D56, pad(["    JSR SysRowBase"], 3, 16)),
        # the rest of $2D46 (the times-40 and the buffer base it adds): never
        # reached, as RowBase returns to $2D46's caller; its bases name buffer
        # row 0, which the buffers no longer hold (FINDINGS "The top rows as
        # objects")
        0x2D56: (0x2D78, pad([], 0, 0x22)),
        # speed (enhancement): the fills' store loops, 11 cycles a byte row by
        # row, done 8 rows at a time column by column (STA abs,X, 5 a byte)
        # by the code in cart RAM at $7203 (sys7800.asm, ;;; RAMFILL). The
        # setup before ($2DA4, RowBase, the column) and the exit after ($17,
        # $06) stay the game's. The rectangle: its value, stride 40 and row
        # count, then the passes. The pattern: to the RAM code, and here the
        # 4-row store block it patches (at $2D19; the BPL's operand is set
        # for each block; now in the fast fill's own RAM, as this page is in
        # ROM: FINDINGS "RAM and fixed ROM: step 5"). FINDINGS "The fast fill"
        0x2CE0: (0x2CFB, pad(["    LDA Z_02", "    STA FL_VAL", "    LDA #1", "    STA FL_STRIDE",
                              "    LDA Z_0D", "    STA FL_COUNT", "    JSR RfPass", "    JMP L_2CFB"], 21, 27)),
        # the framebuffers' rows are one page apart (FINDINGS "display lists by
        # the 7800's rules"): the game's steps to the next row
        # (the common case inline, 13 cycles as the game's ADC; the call only
        # at a column's foot, 1 row in 51: FINDINGS "Performance")
        0x295F: (0x296A, ["    DEC Z_15", "    LDA Z_15", "    CMP #$%02X" % (FB_PBOT - 1), "    BNE RowStepA",
                          "    JSR SysRowWrap", "RowStepA:"]),     # blitter A
        0x2B5A: (0x2B64, pad(["    JSR SysRowNextC"], 3, 10)),      # the mirrored blitter
        0xAD83: (0xAD89, ["    JSR SysCopyBuf"]),                   # the buffer copy
        # its set-up and page loop ($AD8C, $ADCA), reached only from the two
        # calls above: dead, and their XEGS end pointers name buffer rows the
        # port no longer has (FINDINGS "The status bar's rows given back")
        0xAD8C: (0xADE4, []),
        0x2D16: (0x2D3E, pad(["    JMP RfPattern"], 3, 40)),   # (its store block: in RAMFILL)
        # speed (enhancement): the row times 40. The game's $2D78 is a
        # general 8x8 shift-and-add multiply ($2DA1 x $2DA2, 8 turns, about
        # 290 cycles), and every draw call pays it. Its only caller is the
        # row address, always with 40 (the jump-table entry $2CC6 has no
        # caller in any scene), so: (4r + r) x 8, about 60 cycles. It leaves
        # $2DA1-$2DA3 as they were, which nothing reads (FINDINGS "The row
        # address, faster")
        0x2D78: (0x2DA1, pad(["    LDA #$00", "    STA Z_15",
                              "    LDA L_2DA1", "    ASL A", "    ROL Z_15",
                              "    ASL A", "    ROL Z_15",           # 4r
                              "    CLC", "    ADC L_2DA1", "    BCC RowTimes8",
                              "    INC Z_15",                         # 5r
                              "RowTimes8:", "    ASL A", "    ROL Z_15", "    ASL A", "    ROL Z_15",
                              "    ASL A", "    ROL Z_15",           # 40r
                              "    STA Z_14", "    RTS"], 33, 41)),
        # the status bar as objects (FINDINGS "The status bar as objects"):
        # the game's status routines (the clear, the arrows, their images)
        # set the arrows the buffer being drawn shows and build its list
        # (ScStBuild); scene 0 calls the three entries directly
        **STATUS_CODE,
        0x280F: (0x284E, pad(["    JMP SysClearBuf"], 3, 63)),
        # the game's DLI handler ($1026) ends PLA/TAY/PLA/TAX/PLA/RTI; the
        # port enters it straight from the NMI (no second interrupt frame) and
        # takes it out through DliExit, which does the NMI's end-of-DLI work
        # (FINDINGS "The NMI's cost")
        0x1034: (0x103A, pad(["    JMP SysDliExit"], 3, 6)),
        # (the blitters' self-modifying (zp),Y operand at $2926 and $2B11,
        # the address of $14: gone with their set-ups, BlSetup above)
        # NMIEN is write-only: on the XEGS "LDA NMIEN / ORA #$80 / STA NMIEN"
        # reads $FF and so turns the vertical blank on as well as DLIs (the
        # scene loader had turned both off). The port's NMIEN is a readable
        # shadow, so read what the XEGS reads (FINDINGS, "Scene 1")
        0x0EA1: (0x0EA4, ["    LDA #$FF", "    NOP"]),
        # the keyboard, gone (there is none): every read of it and the code only
        # they reach. The console keys cover what matters (START restarts, at
        # the ending too; SELECT pauses; FINDINGS, "The keyboard comes out").
        # The move dispatch at $AE78 takes the key code in A (0 when no key)
        # and, on the same path, the joystick's fire flags ($47 punch, $46
        # kick): Space and + * (walk) in walking mode; Q A Z, W S X (the moves
        # by key) and B (bow) after $AEAB, all compared against A. With no
        # keyboard A is always 0 there, so the key tests go and the joystick
        # branches ($AED0, $AEF7, $AF1B, $AF27) stay; the bow by joystick (up
        # and fire) is unaffected. The exit $AEB1 is every move's and stays.
        0xAE78: (0xAEAB, ["    LDA #$00"]),
        0xAEC4: (0xAED0, ["    JMP L_AEE5"]),
        0xAED5: (0xAEE5, []),
        0xAEEB: (0xAEF7, ["    JMP L_AF33"]),
        0xAEFC: (0xAF0F, []),
        0xAF20: (0xAF24, []),
        0xAF2C: (0xAF33, []),
        # play: Esc (pause), J/K (joystick or keys), Ctrl-R (next scene) and
        # Ctrl-N (enemy health 1), the last two developer cheats
        0xB71E: (0xB773, ["    RTS"]),
        0xB773: (0xB780, []),
        # the Esc pause loop, reached only from those
        0xB785: (0xB7B1, []),
        # the vertical blank's key repeat (SKSTAT), keeping its $F2 countdown
        0x1004: (0x101F, pad(["    RTS"], 1, 27)),
        # the keyboard interrupt: IRQST and KBCODE (the 7800 raises no IRQ)
        0x10FE: (0x1123, pad(["    PLA", "    RTI"], 2, 37)),
        # dead XEGS code the port replaces, removed to make room in the fixed
        # bank (bank 15 may change size): the 8K copy routine (called only by
        # the boot and the loader) and the cartridge boot itself
        0xB2CC: (0xB2EC, []),
        0xB7B1: (0xB7DB, []),
        # the sound's envelope (engine part 1, $1097-$10C0): a note's attack
        # counts its voice's volume ($0E,X) up by one till it equals the
        # target ($1E,X), and only up; a note begun while the voice is still
        # above its target (the last note not yet decayed) counted on through
        # $10-$FF into the distortion bits, a buzzing sawtooth, till it wrapped
        # round to the target. The attract's princess room did it at this
        # port's speed (the cutscene's notes are timed by its own loops, the
        # game's events by flips; the XEGS's timing never hit it): stop at or
        # above the target (FINDINGS "The princess room's sound")
        0x10BC: (0x10BE, ["    BCS L_10C1"]),
        # the fire button ($0FAC-$0FFA, after the scene check and joystick 2):
        # a two-button joystick's button 1 punches, button 2 kicks; one
        # button still times its press (FINDINGS "Two buttons: punch and kick")
        # (V2 only: v1's fixed bank has no room for it)
        **({0x0FAC: (0x0FFB, pad(["    JMP ScButtons"], 3, 0x0FFB - 0x0FAC))} if V2 else {}),
        # (V2) "the end" a row up, all in the top's rows (_END)
        **({0x2EAE: (0x2EB0, ["    LDA #$5A"])} if V2 else {}),
        # (V2) the game's flip waits (LDA $0AF6 / BMI: the common flip's, bank
        # 15's flip's and its frame count's): the main program builds a list
        # the NMI held back (FINDINGS "The switch frames: built outside the NMI")
        **({0x0872: (0x0877, ["    JSR ScFlipWait", "    BMI L_0872"]),
            0xB627: (0xB62C, ["    JSR ScFlipWait", "    BMI L_B627"]),
            0xB639: (0xB63E, ["    JSR ScFlipWait", "    BMI L_B639"])} if V2 else {}),
        # bank 15's record copies, unrolled (bank 15 may grow)
        0xB071: (0xB07C, unrolled(0x20, 0x70, 16, 0x10, z, z)),
        0xB07D: (0xB088, unrolled(0x70, 0x20, 16, 0x10, z, z)),
        0xB08D: (0xB098, unrolled(0x20, 0x60, 16, 0x10, z, z)),
        0xB099: (0xB0A4, unrolled(0x60, 0x20, 16, 0x10, z, z)),
        0xBA73: (0xBA7D, unrolled(0x70, 0x47F7, 16, 0xFF, z, v47)),
        0xBA7E: (0xBA88, unrolled(0x47F7, 0x70, 16, 0xFF, v47, z)),
    }
    r.update(SCENE_REPLACEMENTS.get(scene, {}))
    return r


# replacements in one scene's own code or data only
SCENE_REPLACEMENTS = {
    # the story (FINDINGS "The story as letter objects"): the loop's scroll,
    # clear and string (JSR $0806 / JSR $78B0 / JSR $7884) become one step
    # that paces the scroll and builds the next picture's lists
    0: {0x785E: (0x7867, pad(["    JSR SysStoryStep"], 3, 9)),
        # the title (FINDINGS "The title as objects"): the logo ($790B, into
        # each buffer) and the copyright ($7918) marked instead of drawn
        0x77CF: (0x77D2, ["    JSR SysTitleLogo"]),
        0x77DF: (0x77E2, ["    JSR SysTitleLogo"]),
        0x77EC: (0x77EF, ["    JSR SysTitleCopy"])},
    # the ending waits for Ctrl-R to restart; without the keyboard it just
    # loops on the console check ($B603), where START restarts
    4: {0x7883: (0x7898, pad(["    JMP L_7876"], 3, 21)),
        # Akuma's drawing (bank 15's JMP $7C50 for the scene's own enemy:
        # $7C50's JMP $7C56) through a wrapper that ends his blits' capture
        # when he is drawn (FINDINGS "Akuma as objects")
        0x7C50: (0x7C53, ["    JSR SysAkW"]),
        # the ending's text as the story's letters (FINDINGS "The ending's text
        # as letter objects"): its drawing ($6200 -> $632E) replaced
        0x7870: (0x7873, ["    JSR SysEndText"])},
}


def column_loop(lim, entry):
    """One of level 1's column loops (INC $06 / INC $06 / JSR piece / LDA
    $06 / CMP #lim / BCC, 13 bytes) as a call to the scene page's column
    routine, which draws the same pieces faster. A and the flags end as the
    loop's did."""
    return pad(["    LDA #$%02X" % lim, "    JSR %s" % entry,
                "    LDA Z_06", "    CMP #$%02X" % lim], 9, 13)


# speed (enhancement): level 1 draws its posts and pillars as columns of
# 1- or 2-row pieces 2 rows apart, one blit call a piece (FINDINGS "The tiny
# sprites are columns"). Scene 6 (Select) has the same code; scene 0's copy
# calls the engine directly and is left alone.
COLUMN_LOOPS = {
    0x6EFB: (0x66, "ScCol68"), 0x6F17: (0x97, "ScCol68"),
    0x6F3D: (0x66, "ScCol68"), 0x6F6B: (0xAA, "ScCol68"),
    0x71A5: (0x97, "ScColA"), 0x7CC0: (0x95, "ScColA"), 0x7CF8: (0x93, "ScColA"),
}
LEVEL1_SCENES = (1, 6)        # their scene pages hold the column routine
for _sc in LEVEL1_SCENES:
    SCENE_REPLACEMENTS.setdefault(_sc, {}).update(
        {a: (a + 13, column_loop(lim, entry)) for a, (lim, entry) in COLUMN_LOOPS.items()})

# Level 1 without the blitter (FINDINGS "Level 1 without the blitter: the data
# and the plan"): in scenes 1 and 6 nothing is drawn into the bitmap below
# the top rows; each draw there is an instance, shown as an object a zone
# reading a window the loader rendered into the bitmap's pages
# (port/l1scene7800.py). S_L1: on (the scene's load sets it); L1_HOME: the
# bank with its code and tables (FARL1 pieces: banks 0 and 4 hold the title's
# data where MARIA's window wants level 1's top pieces); its RAM: the fast
# fill's (never run in level 1; LoadScene copies it in again for the others)
S_L1 = 0x1F7F
L1_HOME = 6                 # (the art bank: room since ART_RELEASE; banks 2 and 3,
L1_LDB = 4                  # (the load's data, read only under the blank list: the shapes'
                            # limits, L1K_LIM, the tiles' pieces' table, L1TSP)
L1_GEN = 0                  # (the load's code, L1Gen and L1TLoad: FARL0 pieces, run under
                            # the blank list: bank 0's MARIA copy is safe then)
L1_CAP = 6                  # levels 2 and 3's pages, had it before) (the draws'
                            # capture: FARL2 pieces, with its lookup table)
L1RAM = 0x2600
L1_CHB = 0x64                      # (level 1's tiles' characters: CHBASE, their 10 line pages
                                   # in cart RAM from $6400: their heads are the band lists', unused in
                                   # level 1; not $58-$63: the front boxes' tables are in $5B-$63's)
# the blitters' module in the fixed bank: its replacements' NOP tails (never
# run: each ends in a jump) given back to the fixed bank's far pieces, and
# the resumes they jump to labelled
# the replacements' dead remains in the fixed bank (FINDINGS "The fixed bank:
# room"): bytes inside a replacement that nothing can reach (the code it
# stands for, or what its jump leaves behind) and no run reads
# (probes/tmp-fixcov.lua over every scene, the attract loop, a game over and
# both recordings forced on): bank 15's buffer copy's old set-up and page
# loop; engine part 1's; the pattern fill's old store block (now in RAMFILL);
# the row address's old buffer base and the multiply, whose entries ($2D53
# inside the replacement, $2CC6 the engine's table) no code reaches; engine
# part 2's. (XEGS start, end exclusive)
# (Bank 15's: only its first part, clear of $ADBB-$ADC3, which some run
# reads, likely as an image's bytes. $2F5A's tail is not dead: it falls into
# $2F66.)
DEAD_RELEASE = [(0xAD8F, 0xADB3), (0x115C, 0x1169), (0x2D19, 0x2D3E),
                (0x2D49, 0x2D56), (0x2D56, 0x2D78), (0x2D78, 0x2DA1), (0x2F69, 0x2F8A)]
# (V2) the blitters' and fills' dead code in the fixed bank, given back:
# every scene captures the game's draws (the tiles sets), so the game's
# blitter module (engine part 2's $2800-$2BFF) and the port's row and bank
# set-up for it never run. Stretches of 32 bytes or more that no run executed
# or read (probes/tmp-romuse.lua: the six scenes scripted, the plain
# cartridge's deaths and game overs, both recordings; FINDINGS "The ROM by
# scene: step 3"). Fixed-bank addresses (start, end exclusive)
# (engine part 2's; the port's own dead routines, RowBase, RowAddr's and
# BlitBank0A's, are left out of the V2 source instead: #V1)
V2_DEAD_RELEASE = [(0xEFDF, 0xEFDF + 419), (0xEEC7, 0xEEC7 + 251), (0xF18E, 0xF18E + 114),
                   (0xEE51, 0xEE51 + 80)]
# (V2) each scene page's game data the CPU never executed or read
# (probes/tmp-romuse.lua's runs: the six scenes scripted, the plain
# cartridge's deaths and game overs, the user's recordings incl. the whole
# game, its ending and versus mode, the ending jumped to, the princess's
# kick; stretches of 16 bytes or more; made by probes/v2release.py --write):
# given back where no scene in the page has an instruction, label or
# relocation (PAGE_RELEASE's test, byte by byte). MARIA reads its own half.
# (XEGS start, end exclusive; FINDINGS "The ROM by scene: step 3")
V2_PAGE_RELEASE = {
    0: [(0x61FF, 0x630C), (0x639A, 0x63C5), (0x664A, 0x6681), (0x668A, 0x691B), (0x6941, 0x6980), (0x6981, 0x69B8), (0x6A11, 0x6A23), (0x6A44, 0x6B4A), (0x6B7C, 0x6B94), (0x6BD2, 0x6C3F), (0x6C81, 0x6D1B), (0x7080, 0x7096), (0x73ED, 0x7400), (0x774C, 0x7760), (0x7793, 0x77CC), (0x7884, 0x78C9), (0x78CC, 0x796F), (0x7976, 0x79D2), (0x7BCB, 0x7C00), (0x7D7D, 0x7DC8), (0x7E92, 0x7FD9)],
    1: [(0x6000, 0x637B), (0x637C, 0x63C5), (0x664A, 0x6681), (0x6682, 0x691B), (0x6941, 0x6980), (0x6981, 0x69B8), (0x6A11, 0x6A23), (0x6A31, 0x6A43), (0x6A44, 0x6B4A), (0x6B7C, 0x6B94), (0x6BD2, 0x6C30), (0x6C81, 0x6D03), (0x7080, 0x7090), (0x73ED, 0x7400), (0x75EE, 0x7600), (0x761B, 0x762F), (0x763B, 0x764F), (0x765B, 0x766F), (0x769A, 0x7700), (0x7BEB, 0x7C00), (0x7D0B, 0x7FE7)],
    2: [(0x6016, 0x60B4), (0x6103, 0x61EC), (0x6274, 0x64D8), (0x64DA, 0x64EE), (0x64F0, 0x65B8), (0x65BA, 0x65F2), (0x6602, 0x6681), (0x6694, 0x691B), (0x691C, 0x6980), (0x6989, 0x6A43), (0x6A44, 0x6AC5), (0x6F9F, 0x7000), (0x70AC, 0x7100), (0x7238, 0x7280), (0x73A3, 0x7400), (0x7501, 0x7580), (0x7689, 0x7700), (0x7CB3, 0x7D00), (0x7DE8, 0x7FE7)],
    3: [(0x6000, 0x63CE), (0x67ED, 0x6800), (0x6923, 0x6980), (0x6D29, 0x6F76), (0x6F79, 0x7000), (0x709B, 0x7100), (0x71C8, 0x7203), (0x72A8, 0x7300), (0x732B, 0x7340), (0x74D3, 0x7700), (0x7B84, 0x7C50), (0x7C60, 0x7FD9)],
    4: [(0x61D4, 0x620E), (0x630B, 0x63DB), (0x6CE3, 0x6D00), (0x6FE4, 0x7000), (0x709B, 0x7100), (0x71C8, 0x7203), (0x723B, 0x7300), (0x7491, 0x7502), (0x7658, 0x76FF), (0x7886, 0x7898)],
}
# (V2) the same in each scene page's game code and common code (XEGS $1203-
# $22FF, $06E8-$0FFF): their data no run touched, the XEGS display lists at
# $1908 first (the builder reads its descriptions, SP_DESC, not them), given
# back by the same byte test (only bytes no scene in the page has an
# instruction, label or relocation at). The same runs (probes/v2release.py);
# scene 5 shares scene 0's page and is in no run
V2_CODE_RELEASE = {
    0: [(0x06E8, 0x0780), (0x07FA, 0x0862), (0x0956, 0x0AF6), (0x0AFF, 0x0B12), (0x0B72, 0x0B98), (0x0BA6, 0x0BDD), (0x0D55, 0x0D70), (0x0D79, 0x0D8B), (0x0DF6, 0x0E09), (0x150D, 0x1530), (0x18CB, 0x1900), (0x1908, 0x1CC4), (0x1DED, 0x1E00), (0x1F09, 0x2000), (0x206D, 0x20C1), (0x2179, 0x2300)],
    1: [(0x0769, 0x0780), (0x07FA, 0x0878), (0x087F, 0x0900), (0x0A12, 0x0B00), (0x0B72, 0x0B98), (0x0BA6, 0x0BDD), (0x0D55, 0x0D67), (0x0D79, 0x0D8B), (0x0EFE, 0x0F18), (0x17DE, 0x1900), (0x1908, 0x1CC4), (0x1F09, 0x2000), (0x205F, 0x2300)],
    2: [(0x0769, 0x0780), (0x0800, 0x0878), (0x087F, 0x0900), (0x0956, 0x0B00), (0x0B72, 0x0B98), (0x0BA6, 0x0BDD), (0x0D55, 0x0D67), (0x0D79, 0x0D8B), (0x0EFC, 0x0F18), (0x1523, 0x1600), (0x18A0, 0x18BF), (0x18D8, 0x1900), (0x1908, 0x2000), (0x208B, 0x2300)],
    3: [(0x0769, 0x0780), (0x0800, 0x0878), (0x087F, 0x0900), (0x0956, 0x0B00), (0x0B72, 0x0B98), (0x0BA6, 0x0BDD), (0x0C3D, 0x0C51), (0x0D55, 0x0D70), (0x0EFF, 0x0F18), (0x15B0, 0x1600), (0x18A2, 0x18BF), (0x18D8, 0x1900), (0x1908, 0x2000), (0x20CF, 0x2300)],
    4: [(0x0769, 0x0780), (0x07F7, 0x0878), (0x087F, 0x0900), (0x0956, 0x0B00), (0x0B72, 0x0B98), (0x0BA6, 0x0BDD), (0x0C3D, 0x0C51), (0x0D43, 0x0D70), (0x0D79, 0x0D8B), (0x0EE8, 0x0F18), (0x14ED, 0x1530), (0x15A3, 0x1600), (0x188C, 0x18BF), (0x18D1, 0x1900), (0x1908, 0x1C80), (0x1CFA, 0x1D0C), (0x1D0F, 0x1D23), (0x1D34, 0x1D48), (0x1D59, 0x1D6D), (0x1D7E, 0x1D92), (0x1DA3, 0x1DC5), (0x1DD2, 0x1E7D), (0x22E5, 0x2300)],
}
ENGINE2_PAD_RELEASE = [(0x2812, 0x284E), (0x289E + 3, 0x28CA), (0x291D, 0x292E),
                       (0x2A70 + 3, 0x2A9C), (0x2AFD, 0x2B19)]
EXTRA_LABELS = {0x28CA, 0x2A9C}
BL_SHV, BL_MODE = CP.TPB_AT, CP.TPB_AT + 2      # (console RAM now, with the TP_* group)
# the top lists' pieces (TopEmit's copies: TPSG_* rows as L1SG_*'s, by
# S_BLPC): their pointers and state, CPU data in cart RAM (TP_BLD: the DLL
# being built, TP_SG: the buffer's row, TP_SGP: each piece's next byte)
TP_BLD, TP_SG, TP_SGP = CP.TPB_AT + 3, CP.TPB_AT + 4, CP.TPB_AT + 5
TP_SO, TP_DLL = CP.TPB_AT + 19, CP.TPDLL_AT    # (each slot's DLL entry's low byte: by its ordinal,
                                                # A 0-9 in DLL_A's page, B 10-19 in DLL_B's)
assert TP_SO < CP.TPB_AT + 20
# levels 2-4's (census: free in scenes 2-4, not their band pieces)
# (with the DLL pages' room past their DLLs: about 36 entries since the
# merged zones, before the band's pieces at $2280/$2380)
# (the smallest first: first fit then leaves the big runs to the big lists,
# the top's last row's with its sky objects, 50 bytes)
TPSEG_A, TPSEG_B = CP.G10_TOP_A, CP.G10_TOP_B   # (consoleplan: the room scenes 2-4 leave)
# scene 0's (S_BLPC $20; free in all of scene 0 after the boot)
TPSEG_S0A, TPSEG_S0B = CP.G20_TOP_A, CP.G20_TOP_B     # (consoleplan: scene 0's room)  # (the blitters' shift routine and mode, BlSetup: CPU data in
                                   # cart RAM, where their module was)
L1_PAL = 5                         # (level 1's tiles from row L1_PALROW down: palette 1's colours
L1_PALROW = 81                     # as the band's colour DLI sets them, copied there by ColTail;
                                   # the split lands too close to row 82 for palette 1: FINDINGS
                                   # "Level 1: the stripe row's colour")


# ------------------------------------------- the vs fight in level 1's page
# The vs fight (scene 6, OPTION at the title: the fight at the gate, a
# non-scrolling section of level 1) is level 1's banks patched at 40 sites
# (FINDINGS "ROM room: what the scene pages duplicate"). It runs in level 1's
# page (SCENE_BANK[6] = 1; bank 5 is free): each site chooses by S_VS, which
# the loader sets ($80 in the vs fight; the game's $D0 can't tell, since the
# vs fight sets it to 1 and plays on), through helpers in a block of the
# page's scene code that held another scene's sprite (VS_BLOCK, never drawn
# in level 1: FINDINGS "The sprite tables walked"). Each helper keeps the
# registers and flags as the instructions it stands for would leave them
# (PHP / BIT S_VS / PLP around the test). Level 1's constant $0B (the vs
# fight's $01) is the free zero-page byte $FF, set by the loader; the
# scene's identity byte ($7FE7: 1, or 6, which makes the vertical blank
# call the vs fight's $0900) is S_SCID. (FINDINGS "The vs fight in level
# 1's page")
VS_SCENE = 6
# the rest of those copies, given back to the page (FINDINGS "Level 1's
# page: the copies no one reads"): scene code bank 7's older copies of
# other scenes' sprites (the princess room's floor $1200, the intro's
# figures $1588-$18BF, Mariko's pieces $1CC4-$1DD7), which no code of
# level 1's or the vs fight's reads (bank-read probe over level 1 to level
# 2's load, a death, the vs fight; the census executed nothing there). The
# build leaves them out of the page and checks the scenes there have no
# instruction, label or relocation in them. (XEGS start, end exclusive)
PAGE_RELEASE = {1: [(0x1203, 0x12C8), (0x1588, 0x18D0), (0x1CC4, 0x1DFB)]}
# and in the other scene pages, the originals of the scene-code sprites
# read from their copies (SPRITE_COPIES, ART_COPIES: the pointers resolve
# to the copy): no read of them in any scene's run, the attract, or the
# user's recording through the finale (two "reads" at $1F00 and $1FA3 are
# the bus cycles of scene 4's branch at $1EFE, the last on its page:
# FINDINGS "The copied sprites' originals given back")
PAGE_RELEASE.update({
    0: [(0x1203, 0x1525), (0x1530, 0x18D8), (0x1CC4, 0x1DFB)],
    2: [(0x1203, 0x1525), (0x1600, 0x18A2), (0x18BF, 0x18D8)],
    3: [(0x1203, 0x1525), (0x1530, 0x15B3), (0x1600, 0x18A2), (0x18BF, 0x18D8)],
    4: [(0x1203, 0x1525), (0x1530, 0x15B3), (0x1600, 0x18A2), (0x18BF, 0x18D8), (0x1C80, 0x1CFA),
        (0x1F00, 0x1FFE)],
})
# the title's, story's and ending's own data, read by nothing now that MARIA
# draws them from its ROM (FINDINGS "The text's data given back"): the
# logo's letters and the second copyright line (scene 0's data), the story's
# strings 5-25 (string 4 is also string 3's), the ending's ten strings.
# $7C50-$7C55 kept: bank 15's jump for the scene's own enemy ($7C50, scene
# 4's Akuma) counts as code in every scene's model, though in scene 0 those
# bytes are a letter's image and the jump is never taken there
PAGE_RELEASE[0] += [(0x7C00, 0x7C50), (0x7C56, 0x7E96), (0x6100, 0x6207), (0x79D2, 0x7BCC)]
PAGE_RELEASE[4] += [(0x620E, 0x6315)]
# the art bank's images no run reads any more (FINDINGS "Levels 2-4 without
# the blitter: room in the art bank"): the fighters' original images, drawn
# from their pre-cut parts in MARIA's ROM since "The fighters as objects:
# step 4", and pieces of the princess's cell no picture draws.
# probes/tmp-romreads.lua over every scene's scripted run, the attract loop,
# the clean run and the level 3/finale recording forced onto the build:
# 1,237 bytes read, all in $9600-$9FEB. The build checks no scene has an
# instruction or relocation there (the pose tables' pointers to them are
# labels, read but not followed). (bank 6 addresses, end exclusive)
ART_RELEASE = [(0x8000, 0x9600), (0x9A74, 0x9EB8)]
# (V2) never released, whatever the runs saw (FINDINGS "The music's records
# released", "The V2 release audit": probes/v2audit.py, v2music.py): data
# the game's own code reads by an index or through a pointer, which a run
# can miss. Every page: the common code's small-sprite tables ($06F4-$0773,
# by character), joystick 2's ($0960-$0975), the sounds' table and records
# ($0D03-$0D8A; run 07's level 4 starts sound $0D, whose record had been
# given back: the driver read placed code as a channel count, 142, and wrote
# into Akuma's capture arrays). Per page: its own indexed tables and the
# tunes' bytes the runs never played (headers' other variants, a list).
# Each table's slice from its index's real range: the cliff fall's
# ($6C52: $6C13/$6C17/$6C1B,X with X $20-$23, from $A1 = $1F) is
# $6C33-$6C3E. The windows' sources' release honours these too
# (V2) the scene pages whose per-page copies take a stub for the top's sky
# (TopSky: a sky top is level 1's, the top's background colour 2, TOPLBG):
# their scenes' tops never have one (run 10 in real play: TOPLBG only 0 in
# banks 2-5; FINDINGS "Run 10"). Bank 4's room for its copies
NO_SKY_PAGES = {4} if V2 else set()
V2_CODE_KEEP = [(0x06F4, 0x0774), (0x0960, 0x0976), (0x0D03, 0x0D8B)]
V2_KEEP_BY_SCENE = {
    0: [(0x6C33, 0x6C3F), (0x795A, 0x7982), (0x7BCC, 0x7BE6), (0x206D, 0x20C1), (0x217A, 0x218E)],
    1: [(0x6C33, 0x6C3F), (0x7603, 0x7683), (0x7FE1, 0x7FF5), (0x205F, 0x2074)],
    2: [(0x7FE1, 0x7FF5), (0x208B, 0x20A0)],
    3: [(0x20CF, 0x20E4)],
    4: [(0x1D0F, 0x1DA3), (0x6318, 0x632E)],
}


def _minus(ranges, keep):
    out = []
    for a, b in ranges:
        parts = [(a, b)]
        for ka, kb in keep:
            parts = [q for (x, y) in parts for q in ((x, min(y, ka)), (max(x, kb), y)) if q[0] < q[1]]
        out += parts
    return out


V2_CODE_RELEASE = {_sc: _minus(_r, V2_CODE_KEEP + V2_KEEP_BY_SCENE.get(_sc, [])) for _sc, _r in V2_CODE_RELEASE.items()}
V2_PAGE_RELEASE = {_sc: _minus(_r, V2_CODE_KEEP + V2_KEEP_BY_SCENE.get(_sc, [])) for _sc, _r in V2_PAGE_RELEASE.items()}
# zero padding no run reads (FINDINGS "Coverage: common and bank 15":
# probes/p7800-coverage.lua over every mode and the user's recording, with
# the original's census on top): in the common code, so in every scene page
# (COMMON_RELEASE), and in the fixed bank's engine parts and bank 15
# (FIXED_RELEASE). Checked like PAGE_RELEASE. (XEGS start, end exclusive)
COMMON_RELEASE = [(0x07E6, 0x0800), (0x0D8B, 0x0E00), (0x0EB5, 0x0F00)]
for _sc in SCENES:
    if _sc in (0, 1, 2, 3, 4):
        PAGE_RELEASE.setdefault(_sc, []).extend(COMMON_RELEASE)
FIXED_RELEASE = [(0x2656, 0x2700), (0x27DB, 0x2800), (0x2DE4, 0x2E00), (0x2FD4, 0x3000),
                 (0x2BC0, 0x2C00), (0x2C00, 0x2CC0),   # (the mirrored blitter's byte table: read from its copy, FT_MIR)
                 (0xAD59, 0xAD75), (0xB2F0, 0xB300)]
# (not the first copyright line, $2193-$2275, though MARIA's ROM draws it now:
# scene 4's model has a relocated pointer at $21F8 inside it)
VS_BLOCK = (0x12C8, 0x1588)        # scenes 2-4's sprites ($12C8 50x10, $14BE 5x20, $1530
                                   # 43x2) and 12 bytes between: no code, label or
                                   # relocation of level 1's there
_S = sysvars()
_VS, _SCID = _S["S_VS"], _S["S_SCID"]


def _pg(a):
    """an XEGS address's 7800 home in level 1's scene page or cart RAM"""
    for name, lo, hi, new, where in REGIONS:
        if lo <= a < hi and (name in ("scode", "sdata", "common") or name.startswith("engine2")):
            return "$%04X" % (a - lo + new)
    raise ValueError("no home for $%04X" % a)


def _ind(lines):
    return [x if x.endswith(":") else "    " + x for x in lines]


def _vs(name, l1, vs):
    """a helper: l1 in level 1, vs in the vs fight; flags kept for both"""
    return (_ind([name + ":", "PHP", "BIT $%04X" % _VS, "BMI %sV" % name, "PLP"] + l1
                 + [name + "V:", "PLP"] + vs))


def _chain(cmp_end, out):
    """the vs fight's form of the branch groups at $7A5A and $7A9F: the same
    tests, every one going on to the group's end"""
    return ["LDA Z_72", "CMP #$FC", "BCS " + out, "CMP #$2E", "BCS " + out,
            "LDA Z_4B", "CMP Z_4C", "BEQ " + out, "LDA Z_52", "BMI " + out,
            "CMP #$31", "BCC " + out, "LDA Z_44", "BNE " + out, "LDA Z_72", out + ":",
            "JMP " + _pg(cmp_end)]


def _jmp(a):
    return "JMP " + _pg(a)


VS_HELPERS = (
    # calls the vs fight skips (JSR: their RTS returns to the site)
    _vs("VsJ6D0C", [_jmp(0x6D0C)], ["RTS"])
    + _vs("VsJ7260", [_jmp(0x7260)], ["RTS"])
    + _vs("VsJ7090", [_jmp(0x7090)], ["RTS"])
    + _vs("VsJ6C30", [_jmp(0x6C30)], ["RTS"])
    # stores and counts it skips
    + _vs("Vs4647", ["STA Z_46", "STA Z_47", "RTS"], ["RTS"])
    + _vs("VsInc5", ["INC Z_52", "INC Z_51", "INC Z_62", "INC Z_72", "RTS"], ["RTS"])
    + _vs("VsInc6", ["INC Z_62", "INC Z_72", "INC Z_52", "INC Z_91", "RTS"], ["RTS"])
    + _ind(["VsDec4:", "DEC Z_72", "PHP", "BIT $%04X" % _VS, "BMI VsDec4V", "PLP",
            "DEC Z_62", "PHP", "VsDec4V:", "PLP", "DEC Z_52", "DEC Z_91", "RTS"])
    + _ind(["Vs10:", "PHP", "BIT $%04X" % _VS, "BMI Vs10V", "PLP", "INC Z_72",
            "PHP", "Vs10V:", "PLP", "DEC Z_37", "RTS"])
    # other values and addresses
    + _vs("Vs25", ["LDA #$00", "STA Z_A3", "RTS"], ["LDA #$01", "STA Z_A3", "RTS"])
    + _vs("Vs38", ["LDA %s,X" % _pg(0x7C06), "RTS"], ["LDA %s,Y" % _pg(0x7C06), "RTS"])
    + _vs("Vs24", ["JMP L_AB00"], [_jmp(0x0976)])
    + _vs("Vs28", ["JMP L_B9A0"], ["PLA", "PLA", _jmp(0x7850)])
    # the sprite tables' two entries (pointer 24's low byte, row 23)
    + _vs("VsLo", ["LDA %s,X" % _pg(0x7603), "RTS"],
          ["PHP", "CPX #24", "BNE VsLoN", "PLP", "LDA #$BA", "RTS", "VsLoN:", "PLP",
           "LDA %s,X" % _pg(0x7603), "RTS"])
    + _vs("VsRow", ["LDA %s,X" % _pg(0x7663), "RTS"],
          ["PHP", "CPX #23", "BNE VsRowN", "PLP", "LDA #$BF", "RTS", "VsRowN:", "PLP",
           "LDA %s,X" % _pg(0x7663), "RTS"])
    # the start-up: level 1's, other values, two more stores, and six of
    # level 1's done before it (entered from $7700: the set-up at $7706 falls
    # into them, A = 1) or not at all (from $7703)
    + _vs("VsJ1F", ["JSR L_B000", _jmp(0x7722)],
          ["STA Z_10", "STA Z_50", "STA Z_AD", "STA Z_AE", "STA Z_5D", "STA Z_5E",
           "JSR L_B000", _jmp(0x7722)])
    + _vs("VsJ03", [_jmp(0x771F)], ["JSR L_B000", _jmp(0x7722)])
    + _vs("VsS1", ["LDA #$01", "STA Z_10", "STA Z_50", "STA Z_AD", "STA Z_AE", "STA Z_5D",
                   "STA Z_5E", "LDA #$30", "RTS"], ["LDA #$22", "RTS"])
    + _ind(["VsS2:", "STA Z_A0", "STA Z_56", "STA Z_90", "PHP", "BIT $%04X" % _VS,
            "BPL VsS2N", "STA Z_62", "VsS2N:", "PLP", "RTS"])
    + _vs("VsS3", ["LDA #$0B", "STA Z_99", "RTS"], ["PHA", "LDA #$00", "STA Z_99", "PLA", "RTS"])
    + _ind(["VsS4:", "JSR L_B003", "PHP", "BIT $%04X" % _VS, "BPL VsS4N",
            "LDA #$22", "STA Z_72", "VsS4N:", "PLP", "RTS"])
    # jumps (JMP in: they leave by JMP)
    + _vs("VsJ16", ["BEQ VsJ16a", "BCS VsJ16b", _jmp(0x780B), "VsJ16a:", _jmp(0x780E),
                    "VsJ16b:", _jmp(0x7830)],
          ["BEQ VsJ16c", _jmp(0x7830), "VsJ16c:", _jmp(0x780B)])
    + _vs("VsJ17", [_jmp(0x2E03)], [_jmp(0x7700)])
    + _vs("VsJ18", ["LDA Z_44", "BNE VsJ18a", _jmp(0x7870), "VsJ18a:", _jmp(0x787A)],
          [_jmp(0x7850)])
    + _vs("VsJ30", [_jmp(0x2E00)], [_jmp(0x7850)])
    + _vs("VsJ21", ["SBC Z_62", "CMP #$3C", "BCC VsJ21a", _jmp(0x793A), "VsJ21a:", _jmp(0x795A)],
          ["SBC Z_62", "CMP #$05", "BCC VsJ21b", _jmp(0x793A), "VsJ21b:", _jmp(0x795A)])
    + _vs("VsJ22", ["LDA Z_4D", "CMP #$02", "BCS VsJ22a", _jmp(0x7960), "VsJ22a:", _jmp(0x7983)],
          ["LDA Z_4D", "CMP #$02", "BCS VsJ22b", "LDA Z_07", "CMP #$20", "BEQ VsJ22b",
           "LDA Z_75", "CMP #$0E", "BCS VsJ22b", "LDA Z_77", "VsJ22b:", _jmp(0x7973)])
    + _vs("VsJ26", ["LDA #$00", "STA Z_40", _jmp(0x79C0)], ["LDA #$00", "STA Z_40", _jmp(0x79B0)])
    + _vs("VsJ33", ["LDA Z_72", "CMP #$FC", _jmp(0x7A5A)], _chain(0x7A76, "VsJ33c"))
    + _vs("VsJ33b", ["LDA Z_72", "BMI VsJ33d", _jmp(0x7A76), "VsJ33d:", _jmp(0x7A79)],
          ["LDA Z_72", _jmp(0x7A76)])
    + _vs("VsJ35", ["LDA Z_72", "CMP #$FC", _jmp(0x7A9F)], _chain(0x7ABB, "VsJ35c"))
    + _vs("VsJ37", ["ADC Z_22", "CMP #$0B", "BCS VsJ37a", _jmp(0x7B7A), "VsJ37a:", _jmp(0x7B7E)],
          ["ADC Z_22", "CMP #$00", _jmp(0x7B7E)])
)
_vs_end = int(_pg(VS_BLOCK[1] - 1)[1:], 16) + 1
# level 3's hawk (FINDINGS "The hawk as objects"): its drawing ($7B09's JSR
# $6980 in the level's loop: its floor shadow, mask and sprite) through a
# wrapper that captures its blits as Akuma's are
SCENE_REPLACEMENTS.setdefault(3, {}).update({0x7B09: (0x7B0C, ["    JSR SysHawkW"])})

VS_REPLACEMENTS = {
    VS_BLOCK[0]: (VS_BLOCK[1], VS_HELPERS + ["VsEnd:", "    .res $%04X-VsEnd,$FF" % _vs_end]),
    # level 1's constant $0B
    0x7007: (0x7009, ["    LDA Z_FF"]),
    0x7293: (0x7295, ["    CMP Z_FF"]),
    0x73C9: (0x73CB, ["    CPX Z_FF"]),
    0x7CB6: (0x7CB8, ["    LDX Z_FF"]),
    0x734D: (0x7355, pad(["    JSR VsDec4"], 3, 8)),
    0x7368: (0x7370, pad(["    JSR VsInc5"], 3, 8)),
    0x73A1: (0x73A9, pad(["    JSR VsInc6"], 3, 8)),
    0x745D: (0x7460, ["    JSR VsJ6D0C"]),
    0x7502: (0x7505, ["    JSR VsJ6D0C"]),
    0x7578: (0x757C, pad(["    JSR Vs10"], 3, 4)),
    0x7683: (0x7686, ["    JSR VsLo"]),
    0x768D: (0x7690, ["    JSR VsRow"]),
    0x7703: (0x7706, ["    JMP VsJ03"]),
    0x771F: (0x7722, ["    JMP VsJ1F"]),
    0x772C: (0x773C, pad(["    JSR VsS1"], 3, 16)),
    0x77A1: (0x77A7, pad(["    JSR VsS2"], 3, 6)),
    0x77CF: (0x77D3, pad(["    JSR VsS3"], 3, 4)),
    0x77D3: (0x77D6, ["    JSR VsS4"]),
    0x77F4: (0x77F8, pad(["    JSR Vs4647"], 3, 4)),
    0x7807: (0x780B, pad(["    JMP VsJ16"], 3, 4)),
    0x7855: (0x7858, ["    JMP VsJ17"]),
    0x786C: (0x7870, pad(["    JMP VsJ18"], 3, 4)),
    0x7896: (0x789A, pad(["    JSR Vs4647"], 3, 4)),
    0x78B9: (0x78BD, pad(["    JSR Vs4647"], 3, 4)),
    0x7934: (0x793A, pad(["    JMP VsJ21"], 3, 6)),
    0x795A: (0x7960, pad(["    JMP VsJ22"], 3, 6)),
    0x797A: (0x797D, ["    JSR Vs24"]),
    0x7999: (0x799D, pad(["    JSR Vs25"], 3, 4)),
    0x79AA: (0x79B0, pad(["    JMP VsJ26"], 3, 6)),
    0x79CE: (0x79D1, ["    JSR VsJ7260"]),
    0x79E1: (0x79E4, ["    JSR Vs28"]),
    0x7A03: (0x7A06, ["    JMP VsJ30"]),
    0x7A1E: (0x7A21, ["    JSR VsJ6D0C"]),
    0x7A3C: (0x7A3F, ["    JSR VsJ7090"]),
    0x7A56: (0x7A5A, pad(["    JMP VsJ33"], 3, 4)),
    0x7A72: (0x7A76, pad(["    JMP VsJ33b"], 3, 4)),
    0x7A8F: (0x7A92, ["    JSR VsJ6C30"]),
    0x7A9B: (0x7A9F, pad(["    JMP VsJ35"], 3, 4)),
    0x7B14: (0x7B18, pad(["    JSR Vs4647"], 3, 4)),
    0x7B74: (0x7B7A, pad(["    JMP VsJ37"], 3, 6)),
    0x7C4A: (0x7C4D, ["    JSR Vs38"]),
}
SCENE_REPLACEMENTS[1].update(VS_REPLACEMENTS)
# the scene's identity byte ($7FE7 in the scene data: 0 the title, 1 level 1,
# 6 the vs fight, ...), read by the vertical blank's button routine ($0FA2)
# and bank 15's console code: read from S_SCID, which the loader sets from
# the page (and VsSetup to 6 for the vs fight). (Also: a read in the vertical
# blank no longer depends on the scene page being in: FINDINGS "the frame
# interrupt ... or $7FE7 moves to RAM at scene load".) $B71E's is in the
# keyboard code, removed.
SCID_READS = (0x0FA2, 0xA75E, 0xAF4E, 0xAF5A, 0xAFB6, 0xB5B2)
for _sc in SCENES:
    SCENE_REPLACEMENTS.setdefault(_sc, {}).update(
        {a: (a + 3, ["    LDA $%04X" % _SCID]) for a in SCID_READS})
# the bank no scene page uses now (the vs fight's was): boot data
SPARE_BANK = 5
assert SPARE_BANK not in SCENE_BANK.values()
# the top rows' machinery (the FARART pieces and their tables) lives there:
# it reads only RAM and its own tables, so needs no scene page in the window
TOP_BANK = SPARE_BANK
# (V2: the top rows' machinery, level 1's and the fighters' records in bank
# 6, fixed at $4000 (no switch to reach them); bank 5 the loader's: what only
# a load or the game's end runs, switched to then)
LOADER_BANK = SPARE_BANK
V2_LO_BANK = 6
if V2:
    TOP_BANK = V2_LO_BANK
# and the images copied only at loads (engine part 2, the small-sprite block,
# the fast fill's code: FINDINGS "RAM and fixed ROM: the inventory"), out of
# the art bank
IMG_BANK = TOP_BANK if V2 else SPARE_BANK
# (V2: bank 5 the ending's page, the user's choice 2026-10-16: its CPU half
# scene 4's page (bank 4) byte for byte, its MARIA half the ending's text;
# EndText switches the scene page to it, the next load back. The loader in
# scene 3's page (the most room; a load needs no page in the window: the
# blank list shows, the NMI puts the scene page in itself), the boot's
# image in the fixed bank)
ENDING_BANK = 5
if V2:
    SPARE_BANK = LOADER_BANK = 3
# the scenes that own a scene page (the first of each bank's)
PAGE_SCENES = tuple(s for s in SCENES
                    if SCENE_BANK[s] not in [SCENE_BANK[t] for t in SCENES[:SCENES.index(s)]])
