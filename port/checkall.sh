#!/bin/bash
# Every scene's pictures against its reference, after a change that should
# not alter the picture: the invincible-easy kit, the scripted player
# (playkey.lua FIREFLAG=1 INJECT=1), a screenshot every 2 flips (4 in scenes
# 4 and 6), compared by probes/snapdiff.py. References: the build before
# step 1 (ie1sa, ie2sa, s3ref, s4ref, ie6sa) and, for the attract loop (no
# input), s0base (step 1's: its demo differs from the build before, which was
# wrong there; FINDINGS "Step 1: scene 0, and level 1's cutscene").
#   port/checkall.sh        (builds first)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
A=work/analysis
python port/build7800.py > /dev/null || exit 1
python port/kitopt.py invincible easy -o work/karateka7800-invincible-easy.a78 > /dev/null || exit 1
W() { cygpath -w "$(realpath "$1")"; }
C="$(W work/karateka7800-invincible-easy.a78)"
rm -rf $A/ck1 $A/ck2 $A/ck3 $A/ck4 $A/ck6 $A/ck0
CART="$C" SCENE=1 FIREFLAG=1 INJECT=1 KEYN=99999 SNAPK=$(seq -s, 200 2 1400) END=24000 port/run7800.sh probes/playkey.lua ck1 >/dev/null &
CART="$C" SCENE=2 FIREFLAG=1 INJECT=1 KEYN=99999 SNAPK=$(seq -s, 200 2 1400) END=24000 port/run7800.sh probes/playkey.lua ck2 >/dev/null &
CART="$C" SCENE=3 FIREFLAG=1 INJECT=1 KEYN=99999 SNAPK=$(seq -s, 200 2 1400) END=24000 port/run7800.sh probes/playkey.lua ck3 >/dev/null &
CART="$C" SCENE=4 FIREFLAG=1 INJECT=1 KEYN=99999 SNAPK=$(seq -s, 200 4 900) END=16000 port/run7800.sh probes/playkey.lua ck4 >/dev/null &
CART="$C" SCENE=6 FIREFLAG=1 INJECT=1 KEYN=99999 SNAPK=$(seq -s, 200 4 900) END=16000 port/run7800.sh probes/playkey.lua ck6 >/dev/null &
CART="$C" K0=999999 KEYN=99999 SNAPK=$(seq -s, 2 2 1600) END=20000 port/run7800.sh probes/playkey.lua ck0 >/dev/null &
wait
for p in "1 ie1sa" "2 ie2sa" "3 s3ref" "4 s4ref" "6 ie6sa" "0 s0base"; do
  set -- $p
  echo "scene $1: $(ls $A/ck$1/a7800 2>/dev/null | wc -l) pictures, $(python probes/snapdiff.py $A/ck$1 $A/$2 | grep -vc None) differ from $2"
done
