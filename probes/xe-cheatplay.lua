-- the scripted player (playkey.lua, its env applies) with a cheat script
-- (CHEAT, e.g. probes/xe-easy.lua) loaded first, on the original
-- (MACHINE=xe): for runs that should stay in a level
dofile(os.getenv("CHEAT"))
dofile(os.getenv("PROBES") .. "/playkey.lua")
