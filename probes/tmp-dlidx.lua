-- (debug) the list shown at each flip (S_DLIDX, its XEGS address from the
-- scene page's DLT_LO/HI via the sym) with $D0, to dlidx.log: "flip idx". Runs playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local n, last = 0, nil
local o = io.open("dlidx.log", "w")
TDX = mem:install_read_tap(S.TopFlip, S.TopFlip, "dx", function(a, d)
  if a ~= cpu.state["PC"].value then return d end
  n = n + 1
  local v = mem:read_u8(S.S_DLIDX)
  if v ~= last then o:write(string.format("%d %d D0=%02X\n", n, v, mem:read_u8(0xD0))); o:flush(); last = v end
  return d
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
