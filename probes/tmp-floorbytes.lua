-- at each FlDraw entry and BlitDone in flip FLIP: buffer BUF's (0 A, 1 B) floor bytes, rows R0-R1, columns C0-C1 (from the tiles)
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
local FLIP = tonumber(os.getenv("FLIP") or "459")
local BUF = tonumber(os.getenv("BUF") or "0")
local R0, R1, C0, C1 = 118, 126, 8, 15
local o = io.open("floorbytes.log", "w")
local function byte(r, c)
  local z = (r - 118) // 8
  local h = (z == 3) and 4 or 8
  local l = (r - 118) % 8
  local map = (0x58 + 2 * BUF + z // 2) * 256 + 212 + (z % 2) * 20
  local code = mem:read_u8(map + c // 2)
  return mem:read_u8((0x58 + h - 1 - l) * 256 + code + (c % 2)), code
end
local function dump(tag)
  o:write(tag .. "\n")
  for r = R0, R1 do
    local s = {}
    for c = C0, C1 do local b, code = byte(r, c); s[#s + 1] = string.format("%02X", b) end
    o:write(string.format("  r%d %s\n", r, table.concat(s, " ")))
  end
  o:flush()
end
T1 = mem:install_read_tap(S.FlDraw, S.FlDraw, "fd", function(a, d)
  if a == cpu.state["PC"].value and PLAYKEY_N == FLIP then
    dump(string.format("before draw row %d rows %d buf %02X src %02X%02X col %d w %d mode %02X val %02X", cpu.state["A"].value, zp(0x0D), zp(7), zp(4), zp(3), zp(5), zp(0x0E), zp(0x0F), zp(2)))
  end
  return d end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
