-- (debug) a snapshot at each frame in FSNAP (comma list), as a replay's
-- companion (port/replay.sh NAME REC tmp-framesnap.lua): the ending's text,
-- after the recording's last flip
local M = manager.machine
local want = {}
for t in (os.getenv("FSNAP") or ""):gmatch("%d+") do want[tonumber(t)] = true end
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if want[f] then M.video:snapshot() end
end)
