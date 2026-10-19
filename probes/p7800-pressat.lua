-- presses fire from frame PRESS for 8 frames, and snapshots at FRAMES (comma
-- list); stops after the last (a game started from the title or the story)
local M = manager.machine
local PRESS = tonumber(os.getenv("PRESS") or "1500")
local want, last = {}, 0
for t in (os.getenv("FRAMES") or ""):gmatch("%d+") do local n = tonumber(t); want[n] = true; if n > last then last = n end end
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if fields["P1 Button 1"] then fields["P1 Button 1"]:set_value((f >= PRESS and f < PRESS + 8) and 1 or 0) end
  if want[f] then M.video:snapshot() end
  if f >= last then M:exit() end
end)
