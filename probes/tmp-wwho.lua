-- (debug) a companion of p7800-stateplay.lua (SPALSO): from flip WFROM to
-- WTO (STATEPLAY_N), each write to WLO-WHI (hex) with the writer's PC and
-- S_BANK, runs of one PC folded, to wwho.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local LO, HI = tonumber(os.getenv("WLO"), 16), tonumber(os.getenv("WHI"), 16)
local F0, F1 = tonumber(os.getenv("WFROM") or "0"), tonumber(os.getenv("WTO") or "0")
local log = io.open("wwho.log", "w")
local lastpc, first, lastad, n = -1, 0, 0, 0
local function flush()
  if n > 0 then log:write(string.format("  PC $%04X bank %d: %d writes $%04X-$%04X\n", lastpc, mem:read_u8(sym.S_BANK), n, first, lastad)) end
  n = 0
end
WWHO_TAP = mem:install_write_tap(LO, HI, "wwho", function(a, d)
  local f = _G.STATEPLAY_N or -1
  if f < F0 or f > F1 then return end
  local pc = cpu.state["PC"].value
  if pc ~= lastpc then flush(); lastpc, first = pc, a; log:write(string.format("n%d\n", f)) end
  lastad = a; n = n + 1
end)
emu.register_frame_done(function() flush(); log:flush() end)
