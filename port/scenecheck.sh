#!/bin/bash
# Every scene's pictures at the flips' swaps (checkdl.sh's runs), for one kit
# cart, all six at once, windowless:
#   port/scenecheck.sh NAME CART SYM ZP
# (Windows paths). Output in work/analysis/NAME0..NAME6; compare two sets with
#   python probes/snapcount.py work/analysis/NAMEs work/analysis/OTHERs --over 0
# MAME from $MAME (run7800.sh's default otherwise).
cd "$(dirname "$0")/.."
A=work/analysis; o=$1; c=$2; y=$3; z=$4
for s in 1 2 3; do
  rm -rf $A/${o}$s
  CART="$c" SYMFILE="$y" ZPFILE="$z" SNAPDL=1 SCENE=$s FIREFLAG=1 INJECT=1 KEYN=99999 SNAPK=$(seq -s, 200 2 1400) END=30000 \
    port/run7800.sh probes/playkey.lua ${o}$s >/dev/null 2>&1 &
done
for s in 4 6; do
  rm -rf $A/${o}$s
  CART="$c" SYMFILE="$y" ZPFILE="$z" SNAPDL=1 SCENE=$s FIREFLAG=1 INJECT=1 KEYN=99999 SNAPK=$(seq -s, 200 4 900) END=20000 \
    port/run7800.sh probes/playkey.lua ${o}$s >/dev/null 2>&1 &
done
rm -rf $A/${o}0
CART="$c" SYMFILE="$y" ZPFILE="$z" SNAPDL=1 K0=999999 KEYN=99999 SNAPK=$(seq -s, 2 2 1600) END=24000 \
  port/run7800.sh probes/playkey.lua ${o}0 >/dev/null 2>&1 &
wait
