-- what the port still draws into buffer rows LO-HI (default 118-145, the
-- floor: FINDINGS "The floor: what draws there"): at each RowBase entry
-- (every blit and fill reaches it: the game's $2D46, through a stub), a draw whose rows
-- meet LO-HI, counted by kind (a blit by its return into the blitters'
-- module $7C00-$7FFF, else a fill: rect at TOP_RETRECT, else pattern),
-- source ($03/$04, blits), mode ($0F: 00 OR, FF AND, else store), rows,
-- columns, value ($02, fills; $12/$13 the pattern's), whether the buffer's
-- fighters are drawn yet (FT_SEEN: after them, a front box), the caller
-- (the blitter's or fill's return) and the flip it was in; to floorlog.log
-- at END. Runs playkey.lua (its env applies); ZPMAP the build's map.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local LO, HI = tonumber(os.getenv("LO") or "118"), tonumber(os.getenv("HI") or "145")
local END = tonumber(os.getenv("END") or "6000")
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local function zp(x) return mem:read_u8(ZM[x]) end
local function rd(a) return mem:read_u8(a) end
local function ret(sp, k) return rd(0x100 + ((sp + k) & 0xFF)) + 256 * rd(0x100 + ((sp + k + 1) & 0xFF)) end
local f, cnt, pics = 0, {}, {}
TFL = mem:install_read_tap(S.RowBase, S.RowBase, "tfl", function(a, d)
  if a ~= cpu.state["PC"].value then return d end
  local r0 = zp(6) - 35
  local r1 = r0 + zp(0x0D) - 1
  if r1 < LO or r0 > HI then return d end
  local sp = cpu.state["SP"].value & 0xFF
  local r = ret(sp, 3)                          -- into the blitter or the fill (past
  local up = ret(sp, 5)                         -- RowBase's stub's), and the draw's caller
  local buf = (zp(7) == 0x20) and 1 or 0
  local seen = rd(S.FT_SEEN + buf)
  local k
  if r >= 0x7C00 and r < 0x8000 then
    k = string.format("blit src %02X%02X mode %02X rows %d-%d w %d col %d sh %d %s by %04X",
      zp(4), zp(3), zp(0x0F), r0, r1, zp(0x0E) + 1, zp(0x1E), zp(0x10), seen ~= 0 and "front" or "back", ret(sp, 7))
  elseif r == S.TOP_RETRECT + 1 or r == S.TOP_RETRECT then
    k = string.format("rect cols %d-%d rows %d-%d val %02X %s by %04X", zp(5), zp(9), r0, r1, zp(2), seen ~= 0 and "front" or "back", up)
  else
    k = string.format("pattern cols %d-%d rows %d-%d val %02X/%02X/%02X %s by %04X", zp(5), zp(9), r0, r1, zp(2), zp(0x12), zp(0x13),
      seen ~= 0 and "front" or "back", up)
  end
  local e = cnt[k]
  if not e then e = {n = 0, flips = {}}; cnt[k] = e end
  e.n = e.n + 1
  e.flips[PLAYKEY_N or -1] = true
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    local o = io.open("floorlog.log", "w")
    local ks = {}
    for k in pairs(cnt) do ks[#ks + 1] = k end
    table.sort(ks, function(p, q) return cnt[p].n > cnt[q].n end)
    for _, k in ipairs(ks) do
      local nf = 0
      for _ in pairs(cnt[k].flips) do nf = nf + 1 end
      o:write(string.format("%6d draws %5d flips  %s\n", cnt[k].n, nf, k))
    end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
