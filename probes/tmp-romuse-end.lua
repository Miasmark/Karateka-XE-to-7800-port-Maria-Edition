-- (debug) tmp-romuse.lua's ROM use with a jump into a routine no script
-- reaches (p7800-jumpto.lua: JUMP, AT or ATFLIP; FRAMES its snapshots, e.g.
-- 999999 for none): the ending (scene 4's $B84E) for the ROM by scene
-- (FINDINGS "The ROM by scene: step 3")
dofile(os.getenv("PROBES") .. "/p7800-jumpto.lua")
dofile(os.getenv("PROBES") .. "/tmp-romuse.lua")
