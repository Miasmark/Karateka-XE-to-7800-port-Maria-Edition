-- level 1 without the blitter, phase 0 (FINDINGS "Level 1 without the
-- blitter: the draws as pieces"): every draw into the buffers' rows FB_TOP
-- (65) and down, in order, and each finished picture's buffers, to
-- l1cap.log. Lines:
--   I src hex                        an image's bytes (rows, width, data), once
--   B buf kind mode col row sh src bank seen   a blit drawn (seen: FT_SEEN, after the fighters) (kind A, AR, M, MR; mode the
--                                    game's $0F; row = $06 - $23; FT_IN 0)
--   F buf kind g05 g09 bot g06 g0D g02 g12 nofill   a fill (rect, pat): raw zero
--                                    page; nofill S_NOFILL (it paints nothing)
--   L buf src col row sh limit bank entry z52   the level-1 column routine
--                                    (entry A: ScColA, 68: ScCol68)
--   C buf / K buf                    the game's full clear / copy into buf
--   P n drawn A hex B hex            TopFlip: picture n done (drawn: A or B),
--                                    both buffers' rows 65-145, 40 bytes a row
-- buf: the buffer the game draws ($07: $20 B, else A). FROMF: the first flip
-- logged. Runs playkey.lua.
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
local function buf() return zp(0x07) == 0x20 and "B" or "A" end
local o = io.open("l1cap.log", "w")
-- (module B's entries: in cart RAM at $7C00 once, in the fixed bank at $EE00
-- since "The blitter in the fixed bank")
local KIND = {[0x7C50] = "A", [0x7DC4] = "AR", [0x7F84] = "M", [0x7F8D] = "MR",
              [0xEE50] = "A", [0xEFC4] = "AR", [0xF184] = "M", [0xF18D] = "MR"}
local seen = {}
-- PLAYBACK=1: a recording plays (MAME's -playback), no playkey.lua: the
-- pictures counted here, the run ended at frame END
local PB = os.getenv("PLAYBACK") ~= nil
local npic = 0
local function picn() return PB and npic or (PLAYKEY_N or 0) end
local function on() return picn() >= FROMF end
local function img(src)
  if seen[src] then return end
  seen[src] = true
  local n = 2 + b(src) * b(src + 1)
  local t = {}
  for k = 0, n - 1 do t[#t + 1] = string.format("%02X", b(src + k)) end
  o:write(string.format("I %04X %d %s\n", src, b(S.S_BANK), table.concat(t)))
end
local pend = nil
GLYOK = os.getenv("GLYOK") ~= nil   -- (GLYOK=1: blits with the glyphs in too: scene 0 keeps them in after its story)
T1 = mem:install_read_tap(S.BlitBank, S.BlitBank, "c1", function(a, d)
  if a ~= cpu.state["PC"].value then return d end
  local sp = cpu.state["SP"].value & 0xFF
  local ret = b(0x103 + sp) + 256 * b(0x104 + sp)
  pend = (b(S.FT_IN) == 0 and (GLYOK or b(S.S_GLYIN) == 0)) and {kind = KIND[ret] or string.format("?%04X", ret)} or nil
  return d
end)
T2 = mem:install_read_tap(S.BlitBankKeep, S.BlitBankKeep, "c2", function(a, d)
  if a ~= cpu.state["PC"].value or not pend or not on() then pend = nil; return d end
  local src = zp(0x04) * 256 + zp(0x03)
  local row = (zp(0x06) - 0x23) & 0xFF
  if row + b(src) > 65 or row >= 0x80 then
    img(src)
    o:write(string.format("B %s %s %02X %d %d %d %04X %d %d\n", buf(), pend.kind, zp(0x0F), zp(0x05), row, zp(0x10), src, b(S.S_BANK),
      b(S.FT_SEEN + (zp(0x07) == 0x20 and 1 or 0))))   -- (and FT_SEEN: the buffer's fighters drawn already)
  end
  pend = nil
  return d
end)
local function fill(kind)
  return function(a, d)
    if a ~= cpu.state["PC"].value or not on() then return d end
    o:write(string.format("F %s %s %d %d %d %d %d %02X %02X %d\n", buf(), kind, zp(0x05), zp(0x09), (zp(0x08) - 0x23) & 0xFF,
      (zp(0x06) - 0x23) & 0xFF, zp(0x0D), zp(0x02), zp(0x12), b(S.S_NOFILL)))
    return d
  end
end
T3 = mem:install_read_tap(S.G_L2CCD, S.G_L2CCD, "c3", fill("rect"))
T4 = mem:install_read_tap(S.G_L2D03, S.G_L2D03, "c4", fill("pat"))
local function col(entry)
  return function(a, d)
    if a ~= cpu.state["PC"].value or not on() then return d end
    local src = zp(0x04) * 256 + zp(0x03)
    img(src)
    o:write(string.format("L %s %04X %d %d %d %d %d %s %d\n", buf(), src, zp(0x05), (zp(0x06) - 0x23) & 0xFF,
      zp(0x10), ((cpu.state["A"].value & 0xFF) - 0x23) & 0xFF, b(S.S_BANK), entry, zp(0x52)))
    return d
  end
end
T5 = mem:install_read_tap(S.ScColA, S.ScColA, "c5", col("A"))
T9 = mem:install_read_tap(S.ScCol68, S.ScCol68, "c9", col("68"))
T6 = mem:install_read_tap(S.SysClearBuf, S.SysClearBuf, "c6", function(a, d)
  if a == cpu.state["PC"].value and on() then o:write("C " .. buf() .. "\n") end
  return d
end)
T7 = mem:install_read_tap(S.SysCopyBuf, S.SysCopyBuf, "c7", function(a, d)
  if a == cpu.state["PC"].value and on() then o:write("K " .. (zp(0x07) == 0x40 and "A" or "B") .. " " .. string.format("%02X", zp(0x07)) .. "\n") end
  return d
end)
local function rows(bf)
  local t = {}
  for r = 65, 145 do
    local q = r - 65
    local base = (0x72 - q % 27) * 256 + 16 + 40 * (3 * bf + q // 27)
    for k = 0, 39 do t[#t + 1] = string.format("%02X", b(base + k)) end
  end
  return table.concat(t)
end
T8 = mem:install_read_tap(S.TopFlip, S.TopFlip, "c8", function(a, d)
  if a ~= cpu.state["PC"].value then return d end
  if PB then npic = npic + 1 end
  if not on() then return d end
  o:write(string.format("P %d %s %02X%02X%02X%02X A %s B %s\n", picn(), buf(), zp(0x52), zp(0x50), zp(0x4C), zp(0xE4), rows(0), rows(1)))
  return d
end)
emu.register_frame_done(function() o:flush() end)
if PB then
  local f, END = 0, tonumber(os.getenv("END") or "6000")
  emu.register_frame_done(function() f = f + 1; if f >= END then o:close(); M:exit() end end)
else
  dofile(os.getenv("PROBES") .. "/playkey.lua")
end
