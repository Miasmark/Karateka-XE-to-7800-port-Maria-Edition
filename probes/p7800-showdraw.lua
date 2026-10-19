-- a screenshot of every frame, as completed (frame_done), from flip FROM to
-- TO (playkey.lua's count; it runs, its env applies), and the frames' flip
-- numbers to showdraw.log ("frame flip snapshot#"), to tell a picture shown
-- incomplete from playkey's SNAPK timing (taken at the flip call, mid-frame).
-- END frames.
local M = manager.machine
local FROM, TO = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("TO") or "99999")
local o = io.open("showdraw.log", "w")
local f, k = 0, 0
emu.register_frame_done(function()
  f = f + 1
  local n = PLAYKEY_N or 0
  if n < FROM or n > TO then return end
  M.video:snapshot()
  o:write(string.format("%d %d %d\n", f, n, k))
  k = k + 1
  o:flush()
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
