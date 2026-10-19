-- (debug) a companion of p7800-stateplay.lua (SPALSO): from frame TFROM,
-- every instruction's address (a read at the PC: opcode fetches) kept in a
-- ring of the last RING; when one runs below $0100 (zero page: the crash),
-- the ring and the registers to pcring.log and MAME stops (the forced replay
-- of recording 07 on V2 ending at PC $0065 in level 2; MAME's own trace,
-- under -debug, moved the crash away)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("TFROM") or "0")
local RING = tonumber(os.getenv("RING") or "3000")
local ring, pos, n = {}, 0, 0
local f = 0
local function dump(why)
  local log = io.open("pcring.log", "w")
  log:write(string.format("%s at frame %d; A=%02X X=%02X Y=%02X SP=%02X P=%02X\n", why, f, cpu.state["A"].value,
    cpu.state["X"].value, cpu.state["Y"].value, cpu.state["SP"].value, cpu.state["P"].value))
  local cnt = math.min(n, RING)
  for k = cnt - 1, 0, -1 do
    local i = (pos - 1 - k) % RING
    log:write(string.format("%04X\n", ring[i]))
  end
  local sp = cpu.state["SP"].value
  local s = "stack:"
  for k = 1, 16 do s = s .. string.format(" %02X", mem:read_u8(0x100 + ((sp + k) & 0xFF))) end
  log:write(s .. "\n")
  log:close()
end
local armed = false
emu.register_frame_done(function()
  f = f + 1
  if f == FROM and not armed then
    armed = true
    PCR_TAP = mem:install_read_tap(0x0000, 0xFFFF, "pcr", function(ad, d)
      if ad == cpu.state["PC"].value then
        ring[pos] = ad
        pos = (pos + 1) % RING
        n = n + 1
        if ad < 0x100 and not DONE then
          DONE = true
          dump("zero page")
          M:exit()
        end
      end
      return d
    end)
  end
end)
