-- snapshots at the frames in FRAMES (comma-separated; from power-on), then
-- the run ends at the last. WITHPLAY=1: playkey.lua drives.
local M = manager.machine
local want, last, f = {}, 0, 0
for n in (os.getenv("FRAMES") or ""):gmatch("%d+") do want[tonumber(n)] = true; last = math.max(last, tonumber(n)) end
emu.register_frame_done(function()
  f = f + 1
  if want[f] then M.video:snapshot() end
  if f >= last then M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
