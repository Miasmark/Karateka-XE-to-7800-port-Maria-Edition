-- (debug) playkey.lua, plus: the first CPU write into LO-HI (default DLL A's
-- top entries) after frame F0: the PC, ZP_P1/ZP_P2, and the bytes at
-- SYM_ADDR.TP_BLD.. (TP_BLD TP_SG TP_SGP...), S_BLPC, to dllwrite.log
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = SYM_ADDR
local LO = tonumber(os.getenv("LO") or "220F", 16)
local HI = tonumber(os.getenv("HI") or "2227", 16)
local F0 = tonumber(os.getenv("F0") or "0")
local f, done = 0, false
RU_DW1 = emu.add_machine_frame_notifier(function() f = f + 1 end)
TDW1 = mem:install_write_tap(LO, HI, "dlw", function(a, d)
  if done or f < F0 then return end
  local pc = cpu.state["PC"].value
  if pc < 0x8000 then return end
  done = true
  local o = io.open("dllwrite.log", "w")
  local function b(x) return mem:read_u8(x) end
  o:write(string.format("frame %d: $%04X <- %02X, PC %04X, Y %02X X %02X; ZP_P1 %02X%02X ZP_P2 %02X%02X\n", f, a, d, pc,
    cpu.state["Y"].value & 0xFF, cpu.state["X"].value & 0xFF, b(S.ZP_P1 + 1), b(S.ZP_P1), b(S.ZP_P2 + 1), b(S.ZP_P2)))
  o:write(string.format("TP_BLD %02X TP_SG %02X S_BLPC %02X S_L1 %02X; TP_SGP:", b(S.TP_BLD), b(S.TP_SG), b(S.S_BLPC), b(S.S_L1)))
  for k = 0, 13 do o:write(string.format(" %02X", b(S.TP_SGP + k))) end
  o:write(string.format("\nS_EW %02X S_ETMP %02X S_TDLP %02X%02X TP_SO %02X\n", b(S.S_BANK), b(pc), b(pc + 1), b(pc + 2), b(S.S_EW), b(S.S_ETMP), b(S.S_TDLP + 1), b(S.S_TDLP), b(S.TP_SO)))
  o:close()
end)
