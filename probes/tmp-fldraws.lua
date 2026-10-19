-- from flip FROM to TO: each FlDraw (row, rows, buffer, live), FlBlitP, FlIn, FlOut (fixed-bank / bank 5 entries)
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
local FROM, TO = tonumber(os.getenv("FROM") or "380"), tonumber(os.getenv("TO") or "470")
local o = io.open("fldraws.log", "w")
local function on() local n = PLAYKEY_N or 0; return n >= FROM and n <= TO end
local function tap(name, fn, bank)
  return mem:install_read_tap(S[name], S[name], name, function(a, d)
    if a == cpu.state["PC"].value and on() and (not bank or mem:read_u8(S.S_BANK) == bank) then fn() end
    return d end)
end
T1 = tap("FlDraw", function()
  local sp = cpu.state["SP"].value & 0xFF
  o:write(string.format("flip %d FlDraw row %d rows %d buf %02X src %02X%02X col05 %d col1E %d w0E %d mode %02X val %02X\n", PLAYKEY_N, cpu.state["A"].value, zp(0x0D), zp(7),
    zp(4), zp(3), zp(5), zp(0x1E), zp(0x0E), zp(0x0F), zp(2)))
end)
T2 = tap("FlBlitP", function() o:write(string.format("  FlBlitP src %02X%02X col %d w %d\n", zp(4), zp(3), zp(0x1E), zp(0x0E))) end, 5)
T3 = tap("FlIn", function() o:write(string.format("  FlIn frow %d x %d-%d\n", mem:read_u8(S.FL_FROW), mem:read_u8(S.FL_X0), mem:read_u8(S.FL_X1))) end)
T4 = tap("FlClrBuf", function() o:write(string.format("flip %d ClrBuf buf %02X live %02X\n", PLAYKEY_N, zp(7), mem:read_u8(S.S_FLLIVE))) end)
T5 = tap("FlCpyBuf", function() o:write(string.format("flip %d CpyBuf buf %02X live %02X\n", PLAYKEY_N, zp(7), mem:read_u8(S.S_FLLIVE))) end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
