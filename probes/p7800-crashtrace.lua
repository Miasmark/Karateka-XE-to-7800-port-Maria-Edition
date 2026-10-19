-- the instructions before a crash: from frame FROM, every instruction's PC
-- (and the bank in the window) kept in a ring of RING; when the CPU first
-- executes in LO-HI (hex; where no code is), the ring goes to crashtrace.log
-- and the run ends; or, with SPLO (hex), when the stack pointer first drops
-- below it. WITHPLAY=1: playkey.lua drives.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM = tonumber(os.getenv("FROM") or "0")
local RING = tonumber(os.getenv("RING") or "4000")
local LO, HI = tonumber(os.getenv("LO") or "1B00", 16), tonumber(os.getenv("HI") or "1DFF", 16)
local SPLO = tonumber(os.getenv("SPLO") or "0", 16)
local ring, n, f, done = {}, 0, 0, false
T = mem:install_read_tap(0x0000, 0xFFFF, "ct", function(a, d)
  if done or f < FROM or a ~= cpu.state["PC"].value then return d end
  n = n + 1
  ring[n % RING] = string.format("%04X b%d SP=%02X A=%02X X=%02X Y=%02X", a, mem:read_u8(S.S_BANK),
    cpu.state["SP"].value & 0xFF, cpu.state["A"].value, cpu.state["X"].value, cpu.state["Y"].value)
  if (a >= LO and a <= HI) or (cpu.state["SP"].value & 0xFF) < SPLO then
    done = true
    local o = io.open("crashtrace.log", "w")
    o:write(string.format("frame %d\n", f))
    for i = n - RING + 1, n do if i > 0 and ring[i % RING] then o:write(ring[i % RING] .. "\n") end end
    o:close(); M:exit()
  end
  return d end)
emu.register_frame_done(function() f = f + 1 end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
