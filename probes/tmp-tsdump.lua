-- (debug) at frame FR: the shown DLL as MARIA walks it (flags, lines, list),
-- each flagged zone's number, the CHBASE tables and the NMI's state
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FR = tonumber(os.getenv("FR") or "1000")
local reg = {[0x2C] = 0, [0x30] = 0}
TREG = mem:install_write_tap(0x2C, 0x30, "td_reg", function(a, d) if reg[a] then reg[a] = d end end)
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f ~= FR then return end
  local o = io.open("tsdump.txt", "w")
  local b = function(a) return mem:read_u8(a) end
  o:write(string.format("S_STORY %d step %d NMICHT %d CHNEXT %02X CHONA %d CHONB %d NMIVBI %d\n", b(S.S_STORY),
    b(S.S_STORYT) + 256 * b(S.S_STORYT + 1), b(S.S_NMICHT), b(S.S_CHNEXT), b(S.S_CHONA), b(S.S_CHONB), b(S.S_NMIVBI)))
  local dll = reg[0x2C] * 256 + reg[0x30]
  local line, n = 0, 0
  for e = 0, 90 do
    local fl, hi, lo = b(dll + 3 * e), b(dll + 3 * e + 1), b(dll + 3 * e + 2)
    local dl = hi * 256 + lo
    local tag = ""
    if fl >= 0x80 then n = n + 1; tag = string.format(" DLI %d", n) end
    local q = dl
    local hs = {}
    for k = 1, 4 do
      local b1 = b(q + 1)
      if b1 == 0 then break end
      if (b1 & 0x1F) == 0 then hs[#hs + 1] = string.format("[%02X %02X %02X %02X %02X]", b(q), b1, b(q + 2), b(q + 3), b(q + 4)); q = q + 5
      else hs[#hs + 1] = string.format("[%02X %02X %02X %02X]", b(q), b1, b(q + 2), b(q + 3)); q = q + 4 end
    end
    o:write(string.format("z%02d line %3d h %2d dl %04X%s %s\n", e, line, (fl & 15) + 1, dl, tag, table.concat(hs, " ")))
    line = line + (fl & 15) + 1
    if line >= 243 then break end
  end
  local t = {}
  for i = 0, 62 do t[#t + 1] = string.format("%02X", b(S.TS_CHTV + i)) end
  o:write("CHTV " .. table.concat(t, " ") .. "\n")
  t = {}
  for i = 0, 62 do t[#t + 1] = string.format("%02X", b(S.TS_CHTP + i)) end
  o:write("CHTP " .. table.concat(t, " ") .. "\n")
  o:close()
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
