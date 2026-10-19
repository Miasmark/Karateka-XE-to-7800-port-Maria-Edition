#!/bin/bash
# Every scene's pictures against a reference build, each taken whole at the
# flip's swap (playkey.lua SNAPDL=1: the end of the first frame showing the
# flip's display list), so a build's speed doesn't move the pictures: the
# invincible-easy kit, the scripted player (FIREFLAG=1 INJECT=1), a picture
# every 2 flips (4 in scenes 4 and 6), compared by probes/snapcount.py.
#   port/checkdl.sh            this build (built first) against the reference
#   port/checkdl.sh ref        the reference's pictures made again
# The reference: the step-1 build (fighters in the bitmap, every scene's
# pictures the same as the build before step 1; FINDINGS "The fighters as
# objects: speed"), REF (default its checkpoint).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
A=work/analysis
REF="${REF:-$HERE/../Karateka-Port-checkpoints/2026-10-02_KEEP_enh-step1-band-lists/work}"
W() { cygpath -w "$(realpath "$1")"; }
run() {   # name cart sym zp
  local o=$1 c=$2 y=$3 z=$4
  rm -rf $A/${o}1 $A/${o}2 $A/${o}3 $A/${o}4 $A/${o}6 $A/${o}0
  for s in 1 2 3; do
    CART="$c" SYMFILE="$y" ZPFILE="$z" SNAPDL=1 SCENE=$s FIREFLAG=1 INJECT=1 KEYN=99999 SNAPK=$(seq -s, 200 2 1400) END=30000 \
      port/run7800.sh probes/playkey.lua ${o}$s >/dev/null &
  done
  for s in 4 6; do
    CART="$c" SYMFILE="$y" ZPFILE="$z" SNAPDL=1 SCENE=$s FIREFLAG=1 INJECT=1 KEYN=99999 SNAPK=$(seq -s, 200 4 900) END=20000 \
      port/run7800.sh probes/playkey.lua ${o}$s >/dev/null &
  done
  CART="$c" SYMFILE="$y" ZPFILE="$z" SNAPDL=1 K0=999999 KEYN=99999 SNAPK=$(seq -s, 2 2 1600) END=24000 \
    port/run7800.sh probes/playkey.lua ${o}0 >/dev/null &
  wait
}
if [ "${1:-}" = ref ]; then
  run dlref "$(W "$REF/karateka7800-invincible-easy.a78")" "$(W "$REF/karateka7800.sym")" "$(W "$REF/karateka7800.zp")"
  exit 0
fi
python port/build7800.py > /dev/null || exit 1
python port/kitopt.py invincible easy -o work/karateka7800-invincible-easy.a78 > /dev/null || exit 1
run dlck "$(W work/karateka7800-invincible-easy.a78)" "$(W work/karateka7800.sym)" "$(W work/karateka7800.zp)"
for s in 1 2 3 4 6 0; do
  echo "scene $s: $(python probes/snapcount.py $A/dlck$s $A/dlref$s ${LIST:+--list})"
done
