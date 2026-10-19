-- xe-assetlog.lua -- the original's graphics inventory (port/runxe.sh): every
-- image the blitter draws, with where it came from, per loaded scene and per
-- segment (a segment starts at each screen clear, $280F, and each scene load).
--   B frame scene seg kind src bank rows width caller   a blit ($29D8's header read,
--       taken at its RTS $29FA): kind A (normal, $284E), AR (right-aligned,
--       $29C2), M (mirrored, $2B82), MR ($2B8B), or the caller's address;
--       bank = the cartridge bank in the $8000-$9FFF window (-1 before any
--       switch; only meaningful for sources there); caller = the JSR that
--       called the blitter (the game routine drawing: two returns up the
--       stack, the entries being reached through JMPs); then $05 (the
--       column, bytes) and $06 (the top line: the buffer row is $06 - 35,
--       $2D46), as the caller set them
--   I bank src rows width hex   an image's bytes (header included), the first
--       time that (bank, source) is drawn, and again if they change
--   F frame scene seg kind c0 top c1 bottom   a rectangle fill ($2CCD) or
--       pattern ($2D03): columns $05-$09, lines $06-$08 as the caller set them
--   C frame scene seg           a screen clear ($280F)
--   L frame scene               a scene load finished (the loader, $2F84)
-- A snapshot 60 frames after each clear or load (SNAPS=0: none), numbered
-- in order. CHEAT: the script a recording was made with; WITHPLAY=1 drives
-- input with playkey.lua (MACHINE=xe; its env applies). END frames. To
-- assetlog.log.
if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
local END = tonumber(os.getenv("END") or "20000")
local SNAPS = os.getenv("SNAPS") ~= "0"
local f, seg, bank = 0, 0, -1
local LOADED, PENDING, INNER = 0, 0, false
local seen = {}
local snapat = {}
local o = io.open("assetlog.log", "w")
local KIND = {[0x2851] = "A", [0x29C5] = "AR", [0x2B85] = "M", [0x2B8E] = "MR"}
local function newseg()
  seg = seg + 1
  if SNAPS then snapat[f + 60] = true end
end
XE_ASSET = {
  mem:install_write_tap(0xD500, 0xD5FF, "a-bank", function(a, d) bank = d & 0x0F; return d end),
  mem:install_read_tap(0x00D0, 0x00D0, "a-ld-d0", function(a, d)
    if not INNER and PCs.value == 0x2F75 then PENDING = d end
    return d end),
  mem:install_read_tap(0x2F84, 0x2F84, "a-ld-done", function(a, d)
    if not INNER and PCs.value == 0x2F84 then
      LOADED = PENDING; newseg()
      o:write(string.format("L %d %d\n", f, LOADED))
    end
    return d end),
  mem:install_read_tap(0x280F, 0x280F, "a-clear", function(a, d)
    if not INNER and PCs.value == 0x280F then
      newseg(); o:write(string.format("C %d %d %d\n", f, LOADED, seg))
    end
    return d end),
  mem:install_read_tap(0x2CCD, 0x2CCD, "a-fill", function(a, d)
    if not INNER and PCs.value == 0x2CCD then o:write(string.format("F %d %d %d fill %d %d %d %d\n", f, LOADED, seg,
      mem:read_u8(0x05), mem:read_u8(0x06), mem:read_u8(0x09), mem:read_u8(0x08))) end
    return d end),
  mem:install_read_tap(0x2D03, 0x2D03, "a-pat", function(a, d)
    if not INNER and PCs.value == 0x2D03 then o:write(string.format("F %d %d %d pattern %d %d %d %d\n", f, LOADED, seg,
      mem:read_u8(0x05), mem:read_u8(0x06), mem:read_u8(0x09), mem:read_u8(0x08))) end
    return d end),
  mem:install_read_tap(0x29FA, 0x29FA, "a-blit", function(a, d)
    if INNER or PCs.value ~= 0x29FA then return d end
    INNER = true
    local src = (mem:read_u8(0x03) + 256 * mem:read_u8(0x04) - 2) & 0xFFFF
    local rows, width = mem:read_u8(0x0D), mem:read_u8(0x0E)
    local sp = SPs.value & 0xFF
    local ret = mem:read_u8(0x100 + ((sp + 1) & 0xFF)) + 256 * mem:read_u8(0x100 + ((sp + 2) & 0xFF)) + 1
    local kind = KIND[ret] or string.format("$%04X", ret)
    local caller = (mem:read_u8(0x100 + ((sp + 3) & 0xFF)) + 256 * mem:read_u8(0x100 + ((sp + 4) & 0xFF)) - 2) & 0xFFFF
    local b = (src >= 0x8000 and src < 0xA000) and bank or -1
    o:write(string.format("B %d %d %d %s %04X %d %d %d %04X %d %d\n", f, LOADED, seg, kind, src, b, rows, width, caller,
      mem:read_u8(0x05), mem:read_u8(0x06)))
    -- the bytes: the first time, and again if a sample of them changed
    local key = b * 65536 + src
    local n = 2 + rows * width
    local sample = ""
    for i = 0, math.min(n, 64) - 1, 7 do sample = sample .. string.char(mem:read_u8(src + i)) end
    local s = seen[key]
    if not s or s.n ~= n or s.sample ~= sample then
      seen[key] = {n = n, sample = sample}
      local t = {}
      for i = 0, n - 1 do t[#t + 1] = string.format("%02X", mem:read_u8((src + i) & 0xFFFF)) end
      o:write(string.format("I %d %04X %d %d %s\n", b, src, rows, width, table.concat(t)))
    end
    INNER = false
    return d end),
}
-- BOWPLAY=1: input of its own: fire to start (frame 1800), then every 300
-- frames right for 100 and up + fire (the bow) for 30, a snapshot mid-bow
-- (frame 188 of each 300)
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local function press(n, on) if fields[n] then fields[n]:set_value(on and 1 or 0) end end
local BOWPLAY = os.getenv("BOWPLAY")
emu.register_frame_done(function()
  f = f + 1
  if BOWPLAY and f >= 1800 then
    local ph = (f - 1800) % 300
    local start = f < 1806
    press("P1 Right", ph >= 20 and ph < 120)
    press("P1 Up", ph >= 150 and ph < 180)
    press("P1 Button 1", start or (ph >= 150 and ph < 180))
    if ph == 188 then M.video:snapshot() end   -- (the pose shows ~25 frames after the input)
  end
  if snapat[f] then M.video:snapshot(); snapat[f] = nil end
  if f >= END then o:close(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
