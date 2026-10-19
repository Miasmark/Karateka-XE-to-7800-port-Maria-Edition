-- every blit from frame FROM to TO (FINDINGS "The fighter-box fills
-- dropped"): at each BlitBank entry, its source ($03/$04), column ($05),
-- buffer row ($06 - 35), mode ($0F), shift ($10), buffer ($07), FT_IN and
-- the stack's return addresses, to blits.log. Runs playkey.lua (its env
-- applies); ZPMAP the build's zero-page map.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local function zp(x) return mem:read_u8(ZM[x]) end
local function rd(a) return mem:read_u8(a) end
local function ret(sp, k) return rd(0x100 + ((sp + k) & 0xFF)) + 256 * rd(0x100 + ((sp + k + 1) & 0xFF)) end
local FROM, TO = tonumber(os.getenv("FROM")), tonumber(os.getenv("TO"))
local o = io.open("blits.log", "w")
local f = 0
TBW = mem:install_read_tap(S.BlitBank, S.BlitBank, "tbw", function(a, d)
  if a ~= cpu.state["PC"].value or f < FROM or f > TO then return d end
  local sp = cpu.state["SP"].value & 0xFF
  o:write(string.format("f%d flip %s src %02X%02X col %d row %d mode %02X sh %d buf %02X ftin %d rets %04X %04X %04X %04X %04X\n",
    f, tostring(PLAYKEY_N), zp(4), zp(3), zp(5), zp(6) - 35, zp(0x0F), zp(0x10), zp(7), rd(S.FT_IN),
    ret(sp, 1), ret(sp, 3), ret(sp, 5), ret(sp, 7), ret(sp, 9)))
  return d end)
emu.register_frame_done(function() f = f + 1; if f == TO + 1 then o:close() end end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
