-- (debug) a companion of p7800-stateplay.lua (SPALSO): each frame-end
-- change of the guard's type G_Z3E ($BB), the scene G_ZD0 and the strength
-- G_ZB0, with the flip, to typelog.log (FINDINGS "The messenger's trim":
-- the cutscene guard's accent colour coming in and leaving)
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local log = io.open("typelog.log", "w")
local last = ""
local fr = 0
emu.register_frame_done(function()
  fr = fr + 1
  local s = string.format("type %02X scene %02X str %02X wld %02X %02X l1 %02X", mem:read_u8(S.G_Z3E), mem:read_u8(S.G_ZD0), mem:read_u8(S.G_ZB0), mem:read_u8(S.L1_WLD), mem:read_u8(S.L1_WLD + 1), mem:read_u8(S.S_L1))
  if s ~= last then
    log:write(string.format("f%d n%d %s\n", fr, _G.STATEPLAY_N or -1, s)); log:flush()
    last = s
  end
end)
