-- (debug) the game's display list (S_DLIST) at each TopFlip, with $D0, to
-- dlsample.log; PLAYBACK=1 runs on a recording (END frames)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local o = io.open("dlsample.log", "w")
local n, last = 0, nil
T = mem:install_read_tap(S.TopFlip, S.TopFlip, "dls", function(a, d)
  if a ~= cpu.state["PC"].value then return d end
  n = n + 1
  local v = string.format("%02X%02X", mem:read_u8(S.S_DLIST + 1), mem:read_u8(S.S_DLIST))
  if v ~= last then o:write(string.format("pic %d DL %s D0 %02X\n", n, v, mem:read_u8(0xD0))); last = v; o:flush() end
  return d
end)
local f, END = 0, tonumber(os.getenv("END") or "6000")
emu.register_frame_done(function() f = f + 1; if f >= END then o:close(); M:exit() end end)
