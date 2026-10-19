-- (debug) a companion of p7800-stateplay.lua (SPALSO): in frames PFROM to
-- PTO, each NMI (the vector's first fetch, NMIV hex, default $27CD) and each
-- colour-register write ($21-$3F, (a & 3) ~= 0), in scan lines after that
-- frame's first NMI (from the emulated time), to dlitime.log; MAME exits
-- after PTO
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FR = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local NV = tonumber(os.getenv("NMIV") or "27CD", 16)
local LPS = 59.92 * 263
local o = io.open("dlitime.log", "w")
local f, t0, k = 0, nil, 0
local function on() return f >= FR and f <= TO end
local function ln() return (M.time:as_double() - t0) * LPS end
DT_NMI = mem:install_read_tap(NV, NV, "dtn", function(a, d)
  if on() and a == cpu.state["PC"].value then
    if not t0 then t0 = M.time:as_double() end
    k = k + 1
    o:write(string.format("f%d NMI %d at %.1f\n", f, k, ln()))
  end
  return d
end)
DT_PAL = mem:install_write_tap(0x21, 0x3F, "dtp", function(a, d)
  if on() and t0 and (a & 3) ~= 0 then
    o:write(string.format("f%d   $%02X = %02X at %.1f pc %04X\n", f, a, d, ln(), cpu.state["PC"].value))
  end
end)
emu.register_frame_done(function()
  f = f + 1
  t0, k = nil, 0
  if f > TO then o:close(); M:exit() end
end)
