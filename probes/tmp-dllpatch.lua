-- (debug) playkey.lua, plus: every CPU write into the DLLs ($2200-$23FF)
-- from PCs in the top bank's window while TP_BLD is 0 (TopRefresh's DLL
-- patches), with TP_SO, S_ARG, S_H, S_SLOT, the frame: to dllpatch.log (the
-- first N, default 60)
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = SYM_ADDR
local N = tonumber(os.getenv("N") or "60")
local F0 = tonumber(os.getenv("F0") or "0")
local f, k = 0, 0
local o = io.open("dllpatch.log", "w")
RU_DP1 = emu.add_machine_frame_notifier(function() f = f + 1 end)
TDP1 = mem:install_write_tap(0x2200, 0x23FF, "dlp", function(a, d)
  if k >= N or f < F0 then return end
  local pc = cpu.state["PC"].value
  if pc < (S.TpCpDll or 0) or pc >= (S.TpCpOut or 0) or mem:read_u8(S.S_BANK) ~= 5 then return end
  k = k + 1
  o:write(string.format("f%d pc %04X $%04X <- %02X; TP_SO %d S_ARG %d S_H %d S_SLOT %d\n", f, pc, a, d,
    mem:read_u8(S.TP_SO), mem:read_u8(S.S_ARG), mem:read_u8(S.S_H), mem:read_u8(S.S_SLOT)))
  if k == N then o:close() end
end)
