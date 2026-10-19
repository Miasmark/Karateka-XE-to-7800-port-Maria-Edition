-- where the CPU is, sampled every instruction from frame FROM to TO (the
-- PC, counted by the nearest symbol at or below it; with the bank for
-- $8000-$BFFF), to pcsample.log. ALSO: another probe alongside.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local FROM, TO = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("TO") or "300")
local syms = {}
for name, a in pairs(SYM_ADDR) do syms[#syms + 1] = {a, name} end
table.sort(syms, function(x, y) return x[1] < y[1] end)
local function near(a)
  local lo, hi = 1, #syms
  if a < syms[1][1] then return "-" end
  while lo < hi do local mid = (lo + hi + 1) // 2; if syms[mid][1] <= a then lo = mid else hi = mid - 1 end end
  return syms[lo][2]
end
-- BYSYM: a bank whose code is counted by symbol too (5: the top bank's)
local BYSYM = tonumber(os.getenv("BYSYM") or "5")
local CYC = {7,6,0,8,3,3,5,5,3,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,4,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,3,2,2,2,3,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,4,2,2,2,5,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,2,6,0,6,4,4,4,4,2,5,2,5,5,5,5,5,2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,2,5,0,5,4,4,4,4,2,4,2,4,4,4,4,4,2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7}
-- CYCLES=1: each instruction weighted by its base cycles (the opcode's; no
-- page crossings or taken branches), so a store-heavy loop counts its due
local CYCLES = os.getenv("CYCLES")
local cnt, f, total = {}, 0, 0
local pages = {}
T = mem:install_read_tap(0x0000, 0xFFFF, "pcs", function(a, d)
  if f < FROM or f >= TO or a ~= cpu.state["PC"].value then return d end
  local w = CYCLES and CYC[d + 1] or 1
  total = total + w
  local k
  local bk = (a >= 0x8000 and a < 0xC000) and mem:read_u8(SYM_ADDR.S_BANK) or nil
  if bk == BYSYM then k = string.format("b%d %s", bk, near(a))
  elseif bk then k = string.format("b%d $%02Xxx", bk, a >> 8)
  elseif a < 0x8000 then k = string.format("RAM $%02Xxx", a >> 8)
  else k = near(a) end
  cnt[k] = (cnt[k] or 0) + w
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f == TO then
    local ks = {}
    for k, n in pairs(cnt) do ks[#ks + 1] = {k, n} end
    table.sort(ks, function(x, y) return x[2] > y[2] end)
    local o = io.open("pcsample.log", "w")
    o:write(string.format("frames %d-%d, %d %s\n", FROM, TO, total, CYCLES and "cycles" or "instructions"))
    for i = 1, math.min(tonumber(os.getenv("TOPN") or "40"), #ks) do o:write(string.format("%8d %5.1f%%  %s\n", ks[i][2], 100 * ks[i][2] / total, ks[i][1])) end
    o:close()
  end
end)
if os.getenv("ALSO") then dofile(os.getenv("PROBES") .. "/" .. os.getenv("ALSO")) end
