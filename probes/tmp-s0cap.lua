-- (debug) scene 0's attract loop captured for its worlds: the state record
-- (p7800-staterec.lua, ANYSCENE) and the draws (p7800-l1cap.lua, PLAYBACK:
-- counting its own pictures, GLYOK) in one run, no input. Env: STATE, END.
dofile(os.getenv("PROBES") .. "/p7800-staterec.lua")
SR_T1, SR_TW = T1, TW          -- (the capture names its taps T1 too: kept here)
dofile(os.getenv("PROBES") .. "/p7800-l1cap.lua")
