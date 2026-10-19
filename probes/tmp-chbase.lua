-- (debug) playkey.lua, plus: writes to CHBASE ($34) and CTRL ($3C) during the
-- frames after flip K (3 frames), with the PC and the line estimated from
-- emulated time since the frame began, to chbase.log
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local K = tonumber(os.getenv("K") or "220")
local o = io.open("chbase.log", "w")
local t0, fr, on = nil, 0, 0
RU_CB = emu.add_machine_frame_notifier(function()
  t0 = M.time:as_double()
  if (PLAYKEY_N or 0) >= K and on < 4 then on = on + 1; o:write("-- frame\n"); if on == 4 then o:close() end end
end)
TCB = mem:install_write_tap(0x34, 0x3C, "chb", function(a, d)
  if a ~= 0x34 and a ~= 0x3C then return end
  if on < 1 or on > 3 or not t0 then return end
  o:write(string.format("line %3d $%02X = %02X pc %04X\n", math.floor((M.time:as_double() - t0) * 15734.26), a, d, cpu.state["PC"].value))
end)
