-- every scenery draw of a scene's run, per flip (FINDINGS "Level 1 without
-- the blitter: what it draws"): to l1draws.log
--   flip N buf B zp <the game's zero page $00-$FF, hex>      (at each flip)
--   blit KIND src BANK:ADDR rows R w W mode M row Y col C sh S   (BlitBankKeep;
--        the fighters' parts and captured blits left out)
--   fill rows Y+N cols C0-C1 val V0/V1 kind rect|pat   (RowBase, a fill's call)
--   col src ADDR row Y col C sh S limit L mir M   (the level-1 column routine)
--   end N zp <...>     (TopFlip: the picture done)
-- KIND: A normal, AR right-aligned, M mirrored, MR mirrored right-aligned.
-- Runs playkey.lua (its env applies); END frames; FROMF the first flip logged.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROMF = tonumber(os.getenv("FROMF") or "0")
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local function b(a) return mem:read_u8(a) end
local function zp(x) return b(ZM[x]) end
local o = io.open("l1draws.log", "w")
local KIND = {[0x7C50] = "A", [0x7DC4] = "AR", [0x7F84] = "M", [0x7F8D] = "MR"}
local pend, lastflip = nil, -1
local function on() return (PLAYKEY_N or 0) >= FROMF end
local function flipline()
  local n = PLAYKEY_N or 0
  if n ~= lastflip then
    lastflip = n
    local t = {}
    for z = 0, 255 do t[#t + 1] = string.format("%02X", zp(z)) end
    o:write(string.format("flip %d buf %02X zp %s\n", n, zp(7), table.concat(t)))
  end
end
T1 = mem:install_read_tap(S.BlitBank, S.BlitBank, "l1b1", function(a, d)
  if a ~= cpu.state["PC"].value then return d end
  local sp = cpu.state["SP"].value & 0xFF
  local ret = b(0x103 + sp) + 256 * b(0x104 + sp)
  pend = (b(S.FT_IN) == 0) and {kind = KIND[ret] or string.format("?%04X", ret), mode = zp(0x0F),
    row = (zp(0x06) - 0x23) & 0xFF, col = zp(0x05), sh = zp(0x10)} or nil
  return d
end)
T2 = mem:install_read_tap(S.BlitBankKeep, S.BlitBankKeep, "l1b2", function(a, d)
  if a ~= cpu.state["PC"].value or not pend or not on() then pend = nil; return d end
  local src = zp(0x04) * 256 + zp(0x03)
  local where = src >= 0xC000 and "F" or (src >= 0x8000 and string.format("b%d", b(S.S_BANK)) or "R")
  flipline()
  local zs = ""
  if os.getenv("ZPAT") and string.format("%04X", src) == os.getenv("ZPAT") then
    local t = {}
    for z = 0, 255 do t[#t + 1] = string.format("%02X", zp(z)) end
    zs = " zp " .. table.concat(t)
  end
  o:write(string.format("blit %s src %s:%04X rows %d w %d mode %02X row %d col %d sh %d%s\n", pend.kind, where, src,
    b(src), b(src + 1), pend.mode, pend.row, pend.col, pend.sh, zs))
  pend = nil
  return d
end)
T3 = mem:install_read_tap(S.RowBase, S.RowBase, "l1f", function(a, d)
  if a ~= cpu.state["PC"].value or not on() then return d end
  local sp = cpu.state["SP"].value & 0xFF
  local ret = b(0x103 + sp) + 256 * b(0x104 + sp)
  if ((ret >> 8) - (S.G_L2800 >> 8)) & 0xFF < 4 then return d end     -- (a blit: logged above)
  flipline()
  o:write(string.format("fill rows %d+%d cols %d-%d val %02X/%02X kind %s by %04X\n", (zp(6) - 0x23) & 0xFF, zp(0x0D),
    zp(5), zp(9), zp(7) == 0x20 and 0 or 0, 0, ret == S.TOP_RETRECT and "rect" or "pat", ret))
  return d
end)
T4 = mem:install_read_tap(S.ColA, S.ColA, "l1c", function(a, d)
  if a ~= cpu.state["PC"].value or not on() then return d end
  flipline()
  o:write(string.format("col src %04X row %d col %d sh %d limit %d mir %02X\n", zp(4) * 256 + zp(3),
    (zp(6) - 0x23) & 0xFF, zp(5), zp(0x10), cpu.state["A"].value, zp(0x52)))
  return d
end)
-- the picture's end (TopFlip): the game's zero page as its draws left it
T5 = mem:install_read_tap(S.TopFlip, S.TopFlip, "l1t", function(a, d)
  if a ~= cpu.state["PC"].value or not on() then return d end
  local t = {}
  for z = 0, 255 do t[#t + 1] = string.format("%02X", zp(z)) end
  o:write(string.format("end %d zp %s\n", PLAYKEY_N or 0, table.concat(t)))
  return d
end)
emu.register_frame_done(function() o:flush() end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
