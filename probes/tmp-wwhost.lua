-- (debug) a companion of p7800-stateplay.lua (SPALSO): from flip WFROM to
-- WTO (STATEPLAY_N), each write to WLO-WHI (hex) with the writer's PC and
-- the band emit's state (L1_B, L1_K, L1_FP, L1_I, L1_X, L1_T2), to
-- wwhost.log (FINDINGS "Akuma's red": the doubled doorway part)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local LO, HI = tonumber(os.getenv("WLO"), 16), tonumber(os.getenv("WHI"), 16)
local F0, F1 = tonumber(os.getenv("WFROM") or "0"), tonumber(os.getenv("WTO") or "0")
local log = io.open("wwhost.log", "w")
local function r(n) return mem:read_u8(sym[n]) end
WWHOST_TAP = mem:install_write_tap(LO, HI, "wwhost", function(a, d)
  local f = _G.STATEPLAY_N or -1
  if f < F0 or f > F1 then return d end
  log:write(string.format("n%d $%04X=%02X PC $%04X B%d K%d FP%d I%d X%d T2 %d\n", f, a, d,
    cpu.state["PC"].value, r("L1_B"), r("L1_K"), r("L1_FP"), r("L1_I"), r("L1_X"), r("L1_T2")))
  return d
end)
emu.register_frame_done(function() log:flush() end)
