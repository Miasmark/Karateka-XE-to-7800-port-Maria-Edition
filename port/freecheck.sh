#!/bin/bash
# The free-RAM ledger (layout7800.FREE_RAM) checked in every scene: nothing but
# the boot's clear may write there. Scene 0 (title, story, demo) unplayed, the
# others with the scripted player (playkey.lua FIREFLAG=1 INJECT=1).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
KEYN=9000 END=6000 port/run7800.sh probes/p7800-freecheck.lua free0 >/dev/null &
for s in 1 2 3 4 6; do SCENE=$s FIREFLAG=1 INJECT=1 KEYN=9000 END=14000 port/run7800.sh probes/p7800-freecheck.lua free$s >/dev/null & done
wait
for s in 0 1 2 3 4 6; do echo "scene $s: $(head -1 work/analysis/free$s/freecheck.log 2>/dev/null || echo 'no log')"; done
