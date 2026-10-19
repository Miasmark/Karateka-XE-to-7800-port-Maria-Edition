-- the original's drawing, for planning the fighters as MARIA objects
-- (FINDINGS "The fighters as objects: measured"): every blit and fill with
-- the picture it belongs to (flips of $B60F in play, $0862 in the title and
-- story), to bandlog.log:
--   P frame flip scene                     a flip ($B60F or $0862 called)
--   B frame flip scene kind src bank rows width caller col top shift mode buf
--       a blit (at $29D8's header read, its RTS $29FA): kind A, AR, M, MR (as
--       xe-assetlog.lua); col $05 (bytes, signed), top $06 (buffer row
--       $06 - 35), shift $10 (before the blitter halves it), mode $0F (0 OR,
--       negative AND, else store), buf $07 ($40 A, $20 B)
--   F frame flip scene kind c0 top c1 bottom caller buf colour   a fill
--       ($2CCD) or pattern ($2D03), as xe-assetlog.lua, with its caller,
--       buffer and $02 (the fill's colour in its low 2 bits)
--   C frame flip scene buf                 a screen clear ($280F), of buffer $07
--   K frame flip scene buf                 the buffer copy ($AD8C): the other
--       buffer copied into $07's
-- WITHPLAY=1: playkey.lua's input (MACHINE=xe). CHEAT: a script to dofile()
-- first (the one a recording was made with: run-probe.sh's recordings).
-- END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
local END = tonumber(os.getenv("END") or "20000")
local f, flip, bank, LOADED, PENDING, INNER = 0, 0, -1, 0, 0, false
local o = io.open("bandlog.log", "w")
if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
local KIND = {[0x2851] = "A", [0x29C5] = "AR", [0x2B85] = "M", [0x2B8E] = "MR"}
local function caller(off)
  local sp = SPs.value & 0xFF
  return (mem:read_u8(0x100 + ((sp + off) & 0xFF)) + 256 * mem:read_u8(0x100 + ((sp + off + 1) & 0xFF)) - 2) & 0xFFFF
end
local function fill(kind)
  o:write(string.format("F %d %d %d %s %d %d %d %d %04X %02X %02X\n", f, flip, LOADED, kind,
    mem:read_u8(0x05), mem:read_u8(0x06), mem:read_u8(0x09), mem:read_u8(0x08), caller(1), mem:read_u8(0x07),
    mem:read_u8(0x02)))
end
XE_BAND = {
  mem:install_write_tap(0xD500, 0xD5FF, "b-bank", function(a, d) bank = d & 0x0F; return d end),
  mem:install_read_tap(0x00D0, 0x00D0, "b-ld-d0", function(a, d)
    if not INNER and PCs.value == 0x2F75 then PENDING = d end
    return d end),
  mem:install_read_tap(0x2F84, 0x2F84, "b-ld-done", function(a, d)
    if not INNER and PCs.value == 0x2F84 then LOADED = PENDING end
    return d end),
  mem:install_read_tap(0xB60F, 0xB60F, "b-flip", function(a, d)
    if not INNER and PCs.value == 0xB60F then flip = flip + 1; o:write(string.format("P %d %d %d\n", f, flip, LOADED)) end
    return d end),
  mem:install_read_tap(0x0862, 0x0862, "b-flip0", function(a, d)
    if not INNER and PCs.value == 0x0862 then flip = flip + 1; o:write(string.format("P %d %d %d\n", f, flip, LOADED)) end
    return d end),
  mem:install_read_tap(0x280F, 0x280F, "b-clear", function(a, d)
    if not INNER and PCs.value == 0x280F then
      o:write(string.format("C %d %d %d %02X\n", f, flip, LOADED, mem:read_u8(0x07))) end
    return d end),
  mem:install_read_tap(0xAD8C, 0xAD8C, "b-copy", function(a, d)
    if not INNER and PCs.value == 0xAD8C then
      o:write(string.format("K %d %d %d %02X\n", f, flip, LOADED, mem:read_u8(0x07))) end
    return d end),
  mem:install_read_tap(0x2CCD, 0x2CCD, "b-fill", function(a, d)
    if not INNER and PCs.value == 0x2CCD then fill("fill") end
    return d end),
  mem:install_read_tap(0x2D03, 0x2D03, "b-pat", function(a, d)
    if not INNER and PCs.value == 0x2D03 then fill("pattern") end
    return d end),
  mem:install_read_tap(0x29FA, 0x29FA, "b-blit", function(a, d)
    if INNER or PCs.value ~= 0x29FA then return d end
    INNER = true
    local src = (mem:read_u8(0x03) + 256 * mem:read_u8(0x04) - 2) & 0xFFFF
    local sp = SPs.value & 0xFF
    local ret = mem:read_u8(0x100 + ((sp + 1) & 0xFF)) + 256 * mem:read_u8(0x100 + ((sp + 2) & 0xFF)) + 1
    local kind = KIND[ret] or string.format("$%04X", ret)
    local b = (src >= 0x8000 and src < 0xA000) and bank or -1
    o:write(string.format("B %d %d %d %s %04X %d %d %d %04X %d %d %d %d %02X\n", f, flip, LOADED, kind, src, b,
      mem:read_u8(0x0D), mem:read_u8(0x0E), caller(3), (mem:read_u8(0x05) ~ 0x80) - 0x80, mem:read_u8(0x06),
      mem:read_u8(0x10), (mem:read_u8(0x0F) ~ 0x80) - 0x80, mem:read_u8(0x07)))
    INNER = false
    return d end),
}
emu.register_frame_done(function()
  f = f + 1
  if f >= END then o:close(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
