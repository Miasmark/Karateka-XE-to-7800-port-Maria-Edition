-- (debug) p7800-stateplay.lua's companion (SPALSO): writes to MARIA's colour
-- registers ($20-$2F) during the frames of flips F0-F1 (_G.STATEPLAY_N), with
-- the value, the PC and the line estimated from emulated time since the
-- frame began (this MAME's screen has no vpos), to palflip.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local F0, F1 = tonumber(os.getenv("F0") or "203"), tonumber(os.getenv("F1") or "206")
local o = io.open("palflip.log", "w")
local t0 = nil
local fr = 0
RU_PF = emu.add_machine_frame_notifier(function()
  fr = fr + 1
  t0 = M.time:as_double()
  local n = _G.STATEPLAY_N or 0
  if n >= F0 and n <= F1 then o:write(string.format("-- frame %d flip %d\n", fr, n)) end
end)
TPF = mem:install_write_tap(0x20, 0x2F, "palf", function(a, d)
  local n = _G.STATEPLAY_N or 0
  if n < F0 or n > F1 or not t0 then return end
  local line = math.floor((M.time:as_double() - t0) * 15734.26)
  o:write(string.format("line %3d $%02X = %02X pc %04X\n", line, a, d, cpu.state["PC"].value))
end)
