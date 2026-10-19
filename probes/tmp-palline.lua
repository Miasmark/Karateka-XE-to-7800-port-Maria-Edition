-- (debug) a companion of p7800-stateplay.lua (SPALSO): from flip WFROM to
-- WTO, each write to MARIA's palette registers $21-$3F: the flip, the NMI
-- count then (S_NMICOUNT: which of the frame's interrupts; this MAME's Lua
-- has no beam line), the register, the value and the PC, to palline.log
-- (FINDINGS "The hardware test": the enemy's arrows grey in some pictures)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local NMIC = SYM_ADDR.S_NMICOUNT
local F0, F1 = tonumber(os.getenv("WFROM") or "0"), tonumber(os.getenv("WTO") or "0")
local log = io.open("palline.log", "w")
PALL_TAP = mem:install_write_tap(0x21, 0x3F, "pall", function(a, d)
  local n = _G.STATEPLAY_N or -1
  if n >= F0 and n <= F1 then
    log:write(string.format("n%d nmi %d $%02X=%02X PC $%04X\n", n, mem:read_u8(NMIC), a, d, cpu.state["PC"].value))
  end
  return d
end)
emu.register_frame_done(function() log:flush() end)
