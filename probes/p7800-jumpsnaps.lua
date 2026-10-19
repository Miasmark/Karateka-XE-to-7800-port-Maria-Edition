-- p7800-jumpto.lua, then a snapshot every EVERY frames from FROM to END
local M = manager.machine
local FROM, END2, EVERY = tonumber(os.getenv("FROM")), tonumber(os.getenv("SNAPEND")), tonumber(os.getenv("EVERY") or "2")
dofile(os.getenv("PROBES") .. "/p7800-jumpto.lua")
local g = 0
emu.register_frame_done(function()
  g = g + 1
  if g >= FROM and g <= END2 and (g - FROM) % EVERY == 0 then M.video:snapshot() end
end)
