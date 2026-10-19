"""The fighters' parts each direction needs, from p7800-poses.lua runs: the
lower bodies (fighters7800's blobs; a pose's blob mirrored when the fighter
is the enemy XOR the pose is one of 28-32, $A2BE), the torsos (the game's
images through $A226/$A24C by the upper pose $21; mirrored for the enemy).
    python probes/poses.py work/analysis/ps-*
"""
import sys
sys.path.insert(0, "port")
import fighters7800 as F
from collections import defaultdict

art = F.Art()
m = art.m
blobs = F.lower_blobs(art)
torso_at = art.tab(0xA226, 0xA24C, 38)
seen = defaultdict(int)
where = defaultdict(set)
for d in sys.argv[1:]:
    for ln in open(d + "/poses.log"):
        enemy, lo, up, typ, s36, n = map(int, ln.split())
        seen[(enemy, lo, up)] += n
        where[(enemy, lo, up)].add(d.rsplit("/", 1)[-1])
lower = {"plain": {}, "mirrored": {}}
torso = {"plain": {}, "mirrored": {}}
for (enemy, lo, up), n in seen.items():
    if lo < 42:
        mir = bool(enemy) != (m[0xA2BE + lo] != 0)
        b = blobs[lo]
        lower["mirrored" if mir else "plain"][id(b)] = (len(b), lo)
    if up < 38:
        a = torso_at[up]
        size = m[a] * m[a + 1]
        torso["mirrored" if enemy else "plain"][a] = (size, up)
for name, d in (("lower bodies", lower), ("torsos", torso)):
    for k in ("plain", "mirrored"):
        print("%-13s %-9s %3d parts %5d bytes" % (name, k, len(d[k]), sum(v[0] for v in d[k].values())))
    both = set(d["plain"]) & set(d["mirrored"])
    print("%-13s both ways: %d parts, %d bytes" % (name, len(both), sum(d["plain"][k][0] for k in both)))
print()
print("lower poses drawn by the enemy only in the attract loop (cutscenes):")
for (enemy, lo, up), runs in sorted(where.items()):
    if enemy and runs == {"ps-s0"}:
        print("   lower %d upper %d (%d records)" % (lo, up, seen[(enemy, lo, up)]))
