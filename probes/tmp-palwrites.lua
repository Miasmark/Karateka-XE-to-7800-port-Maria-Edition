-- (debug) every write to MARIA's colour registers ($20-$3F) during frame
-- AT (after flip K): register, value, scanline; to palwrites.log
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local scr = M.screens[":screen"]
local K = tonumber(os.getenv("K") or "400")
local o = io.open("palwrites.log", "w")
local on, f, f0 = false, 0, nil
TW = mem:install_write_tap(0x20, 0x3F, "pal", function(a, d)
  if on then o:write(string.format("line %3d %02X = %02X\n", scr:vpos(), a, d)) end
end)
emu.register_frame_done(function()
  f = f + 1
  if on then on = false; o:close(); M:exit() end
  if not f0 and (PLAYKEY_N or 0) >= K then f0 = f; on = true end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
