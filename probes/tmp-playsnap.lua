-- (debug) playkey.lua's scripted player (its env: SCENE, INJECT, FIREFLAG,
-- END ...) with tmp-recsnap.lua's snapshots and state log beside it
dofile(os.getenv("PROBES") .. "/tmp-recsnap.lua")
dofile(os.getenv("PROBES") .. "/playkey.lua")
