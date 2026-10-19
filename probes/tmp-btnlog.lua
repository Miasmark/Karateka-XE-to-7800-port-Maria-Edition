-- (debug) a recording's buttons and the game's fire state, each frame one
-- changes: button 1 and 2 (the recorded input fields), the game's $46 (kick
-- waiting), $47 (punch waiting), $C4, $DB, $DC (G_Z*), to btnlog.log; MAME
-- exits at END (FINDINGS "The hardware test": the kick button locking up)
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "20000")
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = {port, fld} end end
local function btn(name)
  local pf = fields[name]
  if not pf then return 9 end
  local port, fld = pf[1], pf[2]
  local v = port:read()
  return ((v & fld.mask) ~= (fld.defvalue & fld.mask)) and 1 or 0
end
local o = io.open("btnlog.log", "w")
local f, last = 0, ""
local function r(a) return mem:read_u8(a) end
emu.register_frame_done(function()
  f = f + 1
  local s = string.format("b1 %d b2 %d k46 %02X p47 %02X c4 %02X db %02X dc %02X",
    btn("P1 Button 1"), btn("P1 Button 2"), r(S.G_Z46), r(S.G_Z47), r(S.G_ZC4), r(S.G_ZDB), r(S.G_ZDC))
  if s ~= last then o:write(string.format("f%d %s\n", f, s)); last = s end
  if f >= END then o:close(); M:exit() end
end)
