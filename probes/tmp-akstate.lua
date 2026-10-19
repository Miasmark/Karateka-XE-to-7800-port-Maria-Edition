-- (debug) a companion of p7800-stateplay.lua (SPALSO): from flip AFROM to
-- ATO, at each TopFlip and at each AkLook's return: AKP_ON (a pre-cut pose
-- found), AKP_K, L1_SET, AK_N (A's, B's: captured blits), AK_V, to akstate.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local F0, F1 = tonumber(os.getenv("AFROM") or "0"), tonumber(os.getenv("ATO") or "99999")
local log = io.open("akstate.log", "w")
local function st(what)
  local n = _G.STATEPLAY_N or -1
  if n < F0 or n > F1 then return end
  log:write(string.format("n%d %s AKP_ON=%d AKP_K=%d SET=%d AK_N=%d,%d AK_V=%d,%d\n", n, what,
    mem:read_u8(sym.AKP_ON), mem:read_u8(sym.AKP_K), mem:read_u8(sym.L1_SET),
    mem:read_u8(sym.AK_N), mem:read_u8(sym.AK_N + 1), mem:read_u8(sym.AK_V), mem:read_u8(sym.AK_V + 1)))
  log:flush()
end
AKS_T1 = mem:install_read_tap(sym.AkLookE, sym.AkLookE, "aks1", function(a, d)
  if a == cpu.state["PC"].value then st("AkLookE") end
  return d
end)
