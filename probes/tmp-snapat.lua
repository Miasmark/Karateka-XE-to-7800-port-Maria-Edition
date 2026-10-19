-- (debug) snapshots at the frames in FRAMES (comma list), then exits; for
-- comparing MAME builds or boot paths on one cartridge, no input
local M = manager.machine
local want, last = {}, 0
for t in (os.getenv("FRAMES") or "600"):gmatch("%d+") do local n = tonumber(t); want[n] = true; if n > last then last = n end end
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if want[f] then M.video:snapshot() end
  if f >= last then M:exit() end
end)
