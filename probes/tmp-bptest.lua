-- (debug) needs -debug -debugger script (EXTRA): a breakpoint at BP (hex, a
-- fixed-bank address), the first HITS stops logged with the registers and
-- the stack's top bytes (who called), then on; to bptest.log
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local BP = tonumber(os.getenv("BP") or "E170", 16)
local HITS = tonumber(os.getenv("HITS") or "3")
local o = io.open("bptest.log", "w")
local dbg = M.debugger
local n, armed = 0, false
o:write("debugger: " .. tostring(dbg ~= nil) .. "\n")
RU_BP = emu.add_machine_frame_notifier(function()
  if not armed and dbg then
    cpu.debug:bpset(BP, "1", "")
    armed = true
  end
end)
RU_BPP = emu.register_periodic(function()
  if not dbg or dbg.execution_state ~= "stop" then return end
  local pc = cpu.state["PC"].value
  local sp = cpu.state["SP"].value & 0xFF
  n = n + 1
  o:write(string.format("stop %d at $%04X, SP %02X, stack:", n, pc, sp))
  for k = 1, 6 do o:write(string.format(" %02X", mem:read_u8(0x100 + ((sp + k) & 0xFF)))) end
  o:write("\n")
  if n >= HITS then
    cpu.debug:bpclear()
    o:close()
  end
  dbg.execution_state = "run"
end)
