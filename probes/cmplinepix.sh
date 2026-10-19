#!/bin/bash
# Two builds' pictures compared line for line (p7800-linepix.lua at flip K
# of each scene, the scripted player): the reference build's cart and symbol
# file against the current invincible-easy build. Black is black whichever
# palette holds it: palette 3's colour 1 (the 160B heads') and palette 4's
# colour 2 (the black palette's) count the same; the header lines are left
# out. Differing lines to work/analysis/lp-<scene>.diff.
#   probes/cmplinepix.sh <ref cart> <ref sym> [scenes] [K]
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
REF="$1"; REFSYM="$2"; SCENES="${3:-0 1 2 3 4}"; K="${4:-300}"
w() { cygpath -w "$1"; }
NEW="$HERE/work/karateka7800-invincible-easy.a78"
for s in $SCENES; do
  extra=""; [ "$s" = 0 ] || extra="FIREFLAG=1 INJECT=1"
  env SCENE=$s $extra K=$K KEYN=$((K + 10)) END=$((K * 12 + 2000)) CART="$(w "$REF")" SYMFILE="$(w "$REFSYM")" \
    port/run7800.sh probes/p7800-linepix.lua lpref$s >/dev/null &
  env SCENE=$s $extra K=$K KEYN=$((K + 10)) END=$((K * 12 + 2000)) CART="$(w "$NEW")" \
    port/run7800.sh probes/p7800-linepix.lua lpnew$s >/dev/null &
done
wait
norm() { grep -v '^---' "$1" | tr 'd' 'i'; }
for s in $SCENES; do
  a=work/analysis/lpref$s/linepix.txt; b=work/analysis/lpnew$s/linepix.txt
  if [ ! -s "$a" ] || [ ! -s "$b" ]; then echo "scene $s: no picture"; continue; fi
  diff <(norm "$a") <(norm "$b") > work/analysis/lp-$s.diff
  echo "scene $s: $(grep -c '^<' work/analysis/lp-$s.diff) lines differ of $(norm "$a" | wc -l)"
done
