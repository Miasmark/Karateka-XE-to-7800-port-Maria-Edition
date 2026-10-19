-- (debug) the TIA's sound registers ($15-$1A: AUDC0/1, AUDF0/1, AUDV0/1) as
-- written, their state at each frame's end from FROM to END (exits), to
-- tia.log: "frame C0 C1 F0 F1 V0 V1" when it changed (no input: the attract)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("TFROM") or "0")
local END = tonumber(os.getenv("END") or "6000")
local r = {0, 0, 0, 0, 0, 0}
TIALOG_TAP = mem:install_write_tap(0x15, 0x1A, "tialog", function(a, d)
  r[a - 0x15 + 1] = d
end)
local log = io.open("tia.log", "w")
local f, last = 0, ""
emu.register_frame_done(function()
  f = f + 1
  if f >= FROM then
    local s = string.format("%02X %02X %02X %02X %02X %02X", r[1], r[2], r[3], r[4], r[5], r[6])
    if s ~= last then log:write(string.format("%d %s\n", f, s)); last = s end
  end
  if f >= END then log:close(); M:exit() end
end)
