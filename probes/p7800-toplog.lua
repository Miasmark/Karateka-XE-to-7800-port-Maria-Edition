-- what the game draws into the buffers' top rows (rows above TOPCUT, default
-- 45): every blit and fill reaching there, every full clear and buffer copy,
-- and the buffer flips, with the buffer drawn ($07: $20 B, else A) and the
-- picture count; to toplog.log. The scripted player (playkey.lua, its env
-- applies) drives the game. Lines:
--   P n frame shown scene       a flip (DPPH change): picture n now shown ($D0)
--   B frame buf kind src rows width x top caller    a blit (kind A, AR, M, MR;
--       x = 4 x $05 + $10 / 2 pixels, top = the buffer row $06 - 35)
--   F frame buf kind c0 c1 top bottom value caller  a fill (rect, pattern;
--       columns $05-$09, rows $06 - 35 to $08 - 35)
--   C frame buf                 the game's full clear ($280F)
--   K frame buf                 the game's buffer copy into buf
--   L frame buf kind src rows width x top limit   the level-1 column routine:
--       the piece at top again every 2 rows to the first at or past limit
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
if not SYM_ADDR then dofile(os.getenv("PROBES") .. "/p7800-sym.lua") end
local S = SYM_ADDR
local CUT = tonumber(os.getenv("TOPCUT") or "45")
local Z = {}
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then Z[tonumber(z, 16)] = tonumber(t, 16) end
end
local function z(n) return mem:read_u8(Z[n]) end
local ENTRY = {[0x784E] = "A", [0x79C2] = "AR", [0x7B82] = "M", [0x7B8B] = "MR",
               [0x7CCD] = "rect", [0x7D03] = "pattern"}
local CLEAR, COPY = S.SysClearBuf, S.SysCopyBuf
local log = io.open("toplog.log", "w")
local f, pics, lastd = 0, 0, nil
local function buf() return z(0x07) == 0x20 and "B" or "A" end
local function caller()
  local sp = SPs.value & 0xFF
  local lo, hi = mem:read_u8(0x100 + ((sp + 1) & 0xFF)), mem:read_u8(0x100 + ((sp + 2) & 0xFF))
  return string.format("%04X", (hi * 256 + lo - 2) & 0xFFFF)
end
local inside = false        -- nested entries (a pattern fill calling the rect fill)
T = mem:install_read_tap(0x0000, 0xFFFF, "toplog", function(a, d)
  if a ~= PCs.value then return d end
  if a == CLEAR then log:write(string.format("C %d %s\n", f, buf())); return d end
  if a == COPY then log:write(string.format("K %d %s\n", f, z(0x07) == 0x40 and "A" or "B")); return d end
  if a == S.ScColA or a == S.ScCol68 then
    -- the level-1 column routine: the piece the caller just drew, again 2
    -- rows further down each time until a line at or past the limit (A)
    local src, top = z(0x04) * 256 + z(0x03), z(0x06) - 35
    local mir = a == S.ScCol68 and (z(0x52) >= 0x80 or z(0x52) < 0x14)
    if top < CUT then
      log:write(string.format("L %d %s %s %04X %d %d %d %d %d\n", f, buf(), mir and "MR" or "A", src,
        mem:read_u8(src), mem:read_u8(src + 1), 4 * z(0x05) + (z(0x10) >> 1), top, (cpu.state["A"].value & 0xFF) - 35))
    end
    return d
  end
  local kind = ENTRY[a]
  if not kind then return d end
  if kind == "rect" or kind == "pattern" then
    local top, bot = z(0x06) - 35, z(0x08) - 35
    if top < CUT or bot < CUT then
      log:write(string.format("F %d %s %s %d %d %d %d %02X %s\n", f, buf(), kind, z(0x05), z(0x09), top, bot, z(0x02), caller()))
    end
  else
    local src = z(0x04) * 256 + z(0x03)
    local top = z(0x06) - 35
    if top < CUT then
      log:write(string.format("B %d %s %s %04X %d %d %d %d %s\n", f, buf(), kind, src, mem:read_u8(src), mem:read_u8(src + 1),
        4 * z(0x05) + (z(0x10) >> 1), top, caller()))
    end
  end
  return d end)
-- DUMPTOP=1: at each flip also "D hex", the shown buffer's rows 0 to
-- TOPCUT-1 as they are (40 bytes a row; layout7800.fb_row, the geometry
-- from the symbol file)
local DUMP = os.getenv("DUMPTOP") ~= nil
local BAND, PTOP = S.FB_BAND or 51, S.FB_PTOP or 0x72
local function dumptop(b)
  local t = {}
  for r = 0, CUT - 1 do
    local at = (PTOP - r % BAND) * 256 + 16 + 40 * (3 * b + r // BAND)
    for i = 0, 39 do t[#t + 1] = string.format("%02X", mem:read_u8(at + i)) end
  end
  return table.concat(t)
end
D = mem:install_write_tap(0x002C, 0x002C, "dpph", function(a, d)
  if lastd and d ~= lastd then
    pics = pics + 1
    log:write(string.format("P %d %d %s %d\n", pics, f, d == 0x22 and "A" or "B", z(0xD0)))
    if DUMP then log:write("D " .. dumptop(d == 0x22 and 0 or 1) .. "\n") end
  end
  lastd = d; return d end)
local END = tonumber(os.getenv("END") or "300")
emu.register_frame_done(function()
  f = f + 1
  if f >= END - 1 then log:close() end
end)
