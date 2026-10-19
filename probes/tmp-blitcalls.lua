-- each call of the blitters (G_L284E, G_L2B8B) from flip FROM on: the caller, $03-$06, $ED $84 $D0 $44
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
local FROM = tonumber(os.getenv("FROM") or "400")
local o = io.open("blitcalls.log", "w")
local n = 0
local function tap(at, nm)
  return mem:install_read_tap(at, at, nm, function(a, d)
    if a == cpu.state["PC"].value and (PLAYKEY_N or 0) >= FROM and n < 3000 then
      n = n + 1
      local sp = cpu.state["SP"].value & 0xFF
      local r = mem:read_u8(0x101 + sp) + 256 * mem:read_u8(0x102 + sp)
      local r2 = mem:read_u8(0x103 + sp) + 256 * mem:read_u8(0x104 + sp)
      o:write(string.format("flip %s %s ret %04X %04X bank %02X src %02X%02X col %d row %d | ED %02X 84 %02X D0 %02X 44 %02X 0F %02X\n",
        tostring(PLAYKEY_N), nm, r, r2, mem:read_u8(S.S_BANK), zp(4), zp(3), zp(5), zp(6),
        zp(0xED), zp(0x84), zp(0xD0), zp(0x44), zp(0x0F), cpu.state["X"].value))
      o:flush()
    end
    return d end)
end
T1 = tap(S.G_L284E, "A")
T2 = tap(S.G_L2B8B, "M")
dofile(os.getenv("PROBES") .. "/playkey.lua")
