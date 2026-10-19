-- (debug) the original while a recording plays (CHEAT: the script it was
-- recorded with): each change of the scene number ($D0) logged with its
-- frame to scenesnap.log, and from the frame scene SCENE (default 4) begins,
-- NSNAP (default 30) snapshots, one a frame; MAME exits after them or at END
local M = manager.machine
if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
local mem = M.devices[":maincpu"].spaces["program"]
local SC = tonumber(os.getenv("SCENE") or "4")
local N = tonumber(os.getenv("NSNAP") or "30")
local END = tonumber(os.getenv("END") or "31000")
local o = io.open("scenesnap.log", "w")
local f, last, left = 0, -1, -1
emu.register_frame_done(function()
  f = f + 1
  local d0 = mem:read_u8(0xD0)
  if d0 ~= last then
    o:write(string.format("f%d $D0 %d\n", f, d0))
    if d0 == SC and left < 0 then left = N end
    last = d0
  end
  if left > 0 then M.video:snapshot(); left = left - 1 end
  if left == 0 or f >= END then o:close(); M:exit() end
end)
