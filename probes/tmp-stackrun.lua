-- (debug) playkey.lua, plus: the first time a stack write lands below
-- $0100 + LOW (default $80: the stack running away), the frame, SP, PC
-- and the stack from there to $01FF (return addresses), to stackrun.log
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local LOW = tonumber(os.getenv("LOW") or "80", 16)
local f, done = 0, false
RU_SRF = emu.add_machine_frame_notifier(function() f = f + 1 end)
TSR = mem:install_write_tap(0x0100, 0x01FF, "stkr", function(a, d)
  if done or f < 300 or (cpu.state["SP"].value & 0xFF) >= LOW or (a & 0xFF) < (cpu.state["SP"].value & 0xFF) then return end
  done = true
  local o = io.open("stackrun.log", "w")
  o:write(string.format("frame %d: write $%04X, SP %02X, PC %04X\n", f, a, cpu.state["SP"].value & 0xFF, cpu.state["PC"].value))
  for b = a & 0xFF, 0xFF, 16 do
    o:write(string.format("%04X:", 0x100 + b))
    for k = 0, 15 do
      if b + k <= 0xFF then o:write(string.format(" %02X", mem:read_u8(0x100 + b + k))) end
    end
    o:write("\n")
  end
  o:close()
end)
