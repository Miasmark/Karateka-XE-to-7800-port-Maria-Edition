#!/bin/bash
# A recording forced onto this build (probes/p7800-stateplay.lua), a
# companion probe alongside, windowless, on the MAME the recordings play on
# (their input timing: a78-0287-bs-oldtiming.exe):
#   port/replay.sh NAME RECORD COMPANION [CART]
# RECORD: clean (the user's invincible-easy-02 run, levels 1-4's start: state
# record cref, 19,000 frames) or l3 (the level 3 and finale recording: strec,
# 28,200). CART: the cartridge (work/; default the record's kit cart, made
# from work/karateka7800.a78 into work/rp-*.a78). The symbols and zero-page
# map are work/karateka7800.sym/.zp (or BUILD's), copied beside the cart; SNAPF
# (flips) snapshots in work/analysis/NAME/snap. Other env passes
# through to the probes. Output in work/analysis/NAME.
set -u
cd "$(dirname "$0")/.."
HERE=$PWD; KP=$(cygpath -w "$HERE")
NAME=$1; REC=$2; COMP=$3
MO=/c/Users/thuco/Documents/mame-src/a78-0287-bs-oldtiming.exe
SK="0047,0048,1824,007F,0080,0081,1A22,1A23,1A24,1A25,1A26"
# (and the game's DLI counts in the frame, $0F0E and $0F14 at $1A94/$1A9A:
# TopFlip comes mid-frame, and forcing them there shifted the game's colour
# sets: the arrows grey in a forced replay only; FINDINGS "The flickering
# arrows")
SK="$SK,1A94,1A9A"
# (SKEXTRA: more addresses not forced, e.g. $1880-$18FF: gamestate.txt has
# them, but since the CPU's data moved (2026-10-15) the top lists are there)
SK="$SK${SKEXTRA:+,$SKEXTRA}"
case $REC in
  clean) ST=cref; INP=karateka7800-invincible-easy-02.inp; END=${END:-19000}; OPT="invincible easy" ;;
  l3) ST=strec; INP=karateka7800-level3-invincible-01.inp; END=${END:-28200}; OPT="invincible start-level3" ;;
  # (the user's invincible-easy-03 run, 2026-10-15: levels 1 and 2 to the
  # gate's death, which hung that cart; made on the current a78.exe)
  r03) ST=r03rec; INP=karateka7800-invincible-easy-03.inp; END=${END:-9600}; OPT="invincible easy"
       MO=/c/Users/thuco/Documents/mame-src/a78.exe ;;
  # (the user's invincible-easy-04 run, 2026-10-16: the attract, then the whole
  # game to the ending's text; 2,415 flips)
  r04) ST=r04rec; INP=karateka7800-invincible-easy-04.inp; END=${END:-26600}; OPT="invincible easy"
       MO=/c/Users/thuco/Documents/mame-src/a78.exe ;;
  # (the user's invincible-easy-07 run, 2026-10-16, on the v1 cart (v2ghost's):
  # the whole game to the ending's text, 315 s)
  r07) ST=r07rec; INP=karateka7800-invincible-easy-07.inp; END=${END:-18900}; OPT="invincible easy"
       MO=/c/Users/thuco/Documents/mame-src/a78.exe ;;
  # (the user's invincible-easy-10 run, 2026-10-16, on the v2switch cart:
  # levels 1-4 to the ending's start, 2,163 flips)
  r10) ST=r10rec; INP=karateka7800-invincible-easy-10.inp; END=${END:-16450}; OPT="invincible easy"
       MO=/c/Users/thuco/Documents/mame-src/a78.exe ;;
  # (the user's karateka7800-02 run, 2026-10-17, on the plain v2r10b cart: the
  # cliff fall, a game to level 1's cutscene and a game over; 536 flips; pass
  # the plain cart as CART)
  r02) ST=r02rec; INP=karateka7800-02.inp; END=${END:-4035}; OPT="easy"
       MO=/c/Users/thuco/Documents/mame-src/a78.exe ;;
  *) echo "record: clean, l3, r03, r04, r07, r10 or r02"; exit 1 ;;
esac
CART=${4:-}
if [ -z "$CART" ]; then
  CART=rp-$REC-$NAME.a78
  python port/kitopt.py $OPT -o work/$CART > /dev/null || exit 1
fi
B=${BUILD:-work/karateka7800}        # (BUILD: another build's .sym/.zp base name)
cp "$B.sym" "work/rp-$NAME.sym"; cp "$B.zp" "work/rp-$NAME.zp"
mkdir -p "work/analysis/$NAME"
cd "work/analysis/$NAME"
PLAYBACK=1 NOPLAY=1 NOPLAYKEY=1 SPALSO="$COMP" SKIP="$SK" STATE="$KP\\work\\gamestate.txt" \
  STATEBIN="$KP\\work\\analysis\\$ST\\state.bin" END=$END PROBES="$KP\\probes" \
  SYM="$KP\\work\\rp-$NAME.sym" ZPMAP="$KP\\work\\rp-$NAME.zp" ZPFILE="$KP\\work\\rp-$NAME.zp" \
  $MO a7800 -inipath "$KP\\work\\analysis\\ini" -cart "$KP\\work\\$CART" -rompath "$KP\\roms" \
  -nothrottle -sound none -video none -skip_gameinfo -snapshot_directory snap -input_directory "$KP\\inp" -playback $INP \
  -autoboot_script "$KP\\probes\\p7800-stateplay.lua" ${MOEXTRA:-} > run.out 2>&1    # (MOEXTRA: more MAME options)
