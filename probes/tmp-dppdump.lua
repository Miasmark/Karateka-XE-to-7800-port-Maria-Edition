-- (debug) every write to DPPH/DPPL ($2C/$30) and the bank (BANKSEL $8000)
-- in frames PFROM-PTO, with the frame and PC, to dpp.log; at frame DUMPF the
-- RAM DUMPLO-DUMPHI (hex) and the display list it points to, hex, appended;
-- MAME exits after PTO
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FR = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local DF = tonumber(os.getenv("DUMPF") or "-1")
local LO = tonumber(os.getenv("DUMPLO") or "2780", 16)
local HI = tonumber(os.getenv("DUMPHI") or "27FF", 16)
local o = io.open("dpp.log", "w")
local f = 0
DP_TAP = mem:install_write_tap(0x2C, 0x30, "dpp", function(a, d)
  if f >= FR and f <= TO and (a == 0x2C or a == 0x30) then
    o:write(string.format("f%d %s=%02X pc $%04X\n", f, a == 0x2C and "DPPH" or "DPPL", d, cpu.state["PC"].value))
  end
  return d
end)
DP_TAPB = mem:install_write_tap(0x8000, 0x8000, "bank", function(a, d)
  if f >= FR and f <= TO then
    o:write(string.format("f%d BANK=%02X pc $%04X\n", f, d, cpu.state["PC"].value))
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f == DF then
    local t = {}
    for a = LO, HI do t[#t + 1] = string.format("%02X", mem:read_u8(a)) end
    o:write(string.format("dump $%04X: %s\n", LO, table.concat(t, " ")))
  end
  if f > TO then o:close(); M:exit() end
end)
