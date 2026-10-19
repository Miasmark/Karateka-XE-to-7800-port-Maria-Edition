-- the display MARIA uses at the ends of the frames in FRAMES (comma list):
-- the DLL at DPPH/DPPL, each zone's height and first two objects (4-byte
-- headers: lo, palette/width, hi, x) and the page each zone's rows read, to
-- dlldump.log; stops after the last frame
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local want, last = {}, 0
for t in (os.getenv("FRAMES") or ""):gmatch("%d+") do local n = tonumber(t); want[n] = true; if n > last then last = n end end
local log = io.open("dlldump.log", "w")
local dpph, dppl = 0, 0
T1 = mem:install_write_tap(0x2C, 0x2C, "dpph", function(a, d) dpph = d; return d end)
T2 = mem:install_write_tap(0x30, 0x30, "dppl", function(a, d) dppl = d; return d end)
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if want[f] then
    local dll = dpph * 256 + dppl
    log:write(string.format("frame %d DLL $%04X\n", f, dll))
    local line = 0
    for e = 0, 60 do
      local b0, hi, lo = mem:read_u8(dll + 3 * e), mem:read_u8(dll + 3 * e + 1), mem:read_u8(dll + 3 * e + 2)
      local h = (b0 & 15) + 1
      local dl = hi * 256 + lo
      local objs = {}
      local p = dl
      for k = 1, 3 do
        if mem:read_u8(p + 1) == 0 then break end
        objs[#objs + 1] = string.format("%02X%02X%02X%02X", mem:read_u8(p), mem:read_u8(p + 1), mem:read_u8(p + 2), mem:read_u8(p + 3))
        p = p + (((mem:read_u8(p + 1) & 0x1F) == 0) and 5 or 4)
      end
      log:write(string.format("  line %3d h %2d dli %d DL $%04X %s\n", line, h, b0 >> 7, dl, table.concat(objs, " ")))
      line = line + h
      if line >= 243 then break end
    end
    log:flush()
  end
  if f >= last then log:close(); M:exit() end
end)
