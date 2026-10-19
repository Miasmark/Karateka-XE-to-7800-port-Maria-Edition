-- (debug) a companion of p7800-stateplay.lua (SPALSO): at each TopFlip, the
-- flip count (STATEPLAY_N), the buffer drawn ($07), each buffer's view
-- (L1_V: A's, B's) and the fighters' records (FR_V, FR_C0-FR_C1), to
-- ghost2.log (the ghost at the first guard's gate, FtViewGone)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local zp = {}
for l in io.lines(os.getenv("ZPMAP")) do local z, a = l:match("(%x+) (%x+)"); if z then zp[tonumber(z, 16)] = tonumber(a, 16) end end
local log = io.open("ghost2.log", "w")
GHOST2_TAP = mem:install_read_tap(sym.TopFlip, sym.TopFlip, "ghost2", function(ad, d)
  if ad == cpu.state["PC"].value then
    local s = string.format("n%d $07=%02X V=%02X%02X/%02X%02X", _G.STATEPLAY_N or -1, mem:read_u8(zp[0x07]),
      mem:read_u8(sym.L1_V + 1), mem:read_u8(sym.L1_V), mem:read_u8(sym.L1_V + 3), mem:read_u8(sym.L1_V + 2))
    for i = 0, 3 do
      s = s .. string.format(" %d:%d[%d-%d]", i, mem:read_u8(sym.FR_V + i), mem:read_u8(sym.FR_C0 + i), mem:read_u8(sym.FR_C1 + i))
    end
    log:write(s .. "\n"); log:flush()
  end
  return d
end)
