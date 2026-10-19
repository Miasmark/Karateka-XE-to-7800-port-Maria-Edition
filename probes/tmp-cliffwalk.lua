-- (debug) the cliff fall without a recording: fire pressed from frame FIRE1
-- for 8 frames (the title's start) and again at FIRE2 (the story's skip),
-- then left held from LEFT on; with p7800-l1cap.lua (PLAYBACK=1, so it
-- leaves the input to us) logging level 1's draws; snapshots at SNAPS. END
-- frames (p7800-l1cap's).
local M = manager.machine
local F1 = tonumber(os.getenv("FIRE1") or "400")
local F2 = tonumber(os.getenv("FIRE2") or "-1")
local LEFT = tonumber(os.getenv("LEFT") or "900")
local snaps = {}
for t in (os.getenv("SNAPS") or ""):gmatch("%d+") do snaps[tonumber(t)] = true end
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local f = 0
emu.register_frame_done(function()
  f = f + 1
  local fire = (f >= F1 and f < F1 + 8) or (F2 >= 0 and f >= F2 and f < F2 + 8)
  if fields["P1 Button 1"] then fields["P1 Button 1"]:set_value(fire and 1 or 0) end
  if fields["P1 Left"] then fields["P1 Left"]:set_value(f >= LEFT and 1 or 0) end
  if snaps[f] then M.video:snapshot() end
end)
dofile(os.getenv("PROBES") .. "/p7800-l1cap.lua")
