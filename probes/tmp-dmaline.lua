-- (debug) a companion of p7800-stateplay.lua (SPALSO): every EVERY-th flip
-- (STATEPLAY_N), DUMPF frames after it, the lists MARIA shows (DPPH/DPPL as
-- written, $2C/$30; CTRL's character width, $3C bit 4) priced per line in
-- MARIA cycles: a 4-byte header 8, a 5-byte 10, a direct byte 3, an
-- indirect (character) byte 6 (9 with two-byte characters), the list's end
-- 4 (FINDINGS "DMA: the busiest lines"). MAME's MARIA (maria.cpp, the
-- fork's measured numbers) starts a line at 16, prices no end, and stops
-- drawing at 430: its count is this one + 12. One line a zone to dmaline.log:
--   flip zone line h cycles objects headers5 direct indirect
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local EVERY = tonumber(os.getenv("EVERY") or "10")
local DF = tonumber(os.getenv("DUMPF") or "2")
local log = io.open("dmaline.log", "w")
local dpp = {[0x2C] = 0, [0x30] = 0}
local ctrl = 0x40
DMAL_TAP = mem:install_write_tap(0x2C, 0x3C, "dmal", function(a, d)
  if a == 0x2C or a == 0x30 then dpp[a] = d end
  if a == 0x3C then ctrl = d end
  return d
end)
local last, cnt = -1, 0
local function dump(n)
  local dll = dpp[0x2C] * 256 + dpp[0x30]
  local cw = (ctrl & 0x10) ~= 0 and 9 or 6
  local line = 0
  for z = 0, 40 do
    local b0 = mem:read_u8(dll + 3 * z)
    local dl = mem:read_u8(dll + 3 * z + 1) * 256 + mem:read_u8(dll + 3 * z + 2)
    local h = (b0 & 15) + 1
    local p, cyc, objs, h5, dir, ind = dl, 4, 0, 0, 0, 0
    for k = 1, 120 do
      local m = mem:read_u8(p + 1)
      if m == 0 then break end
      objs = objs + 1
      local w, isind
      if (m & 0x1F) == 0 then         -- (5 bytes: extended; bit 5 of the mode byte: indirect)
        local pw = mem:read_u8(p + 3)
        w = 32 - (pw & 0x1F)
        isind = (m & 0x20) ~= 0
        cyc = cyc + 10
        h5 = h5 + 1
        p = p + 5
      else
        w = 32 - (m & 0x1F)
        isind = false
        cyc = cyc + 8
        p = p + 4
      end
      if isind then
        cyc = cyc + cw * w
        ind = ind + w
      else
        cyc = cyc + 3 * w
        dir = dir + w
      end
    end
    log:write(string.format("%d %d %d %d %d %d %d %d %d\n", n, z, line, h, cyc, objs, h5, dir, ind))
    line = line + h
    if line >= 243 then break end
  end
  log:flush()
end
emu.register_frame_done(function()
  local n = _G.STATEPLAY_N or -1
  if n ~= last then last, cnt = n, 0 else cnt = cnt + 1 end
  if n >= 0 and n % EVERY == 0 and cnt == DF then dump(n) end
end)
