-- (debug) the CPU's PC (and S_BANK) sampled every PERIOD seconds of
-- emulated time from frame P0 to frame P1 (a recording's real playback:
-- tmp-prof.lua's frame-counting copy), each sample put
-- to the nearest symbol at or below it (SYM; bank-blind above $8000: the
-- bank is logged beside it); counts to prof.log at P1, then exit
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FRAME = 0
emu.register_frame_done(function() FRAME = FRAME + 1 end)
local P0 = tonumber(os.getenv("P0") or "220")
local P1 = tonumber(os.getenv("P1") or "260")
local PERIOD = tonumber(os.getenv("PERIOD") or "0.00013")
local addrs = {}
for a, n in pairs(SYM_NAME) do addrs[#addrs + 1] = a end
table.sort(addrs)
local function near(pc)
  local lo, hi = 1, #addrs
  if pc < addrs[1] then return "?" end
  while lo < hi do
    local mid = (lo + hi + 1) // 2
    if addrs[mid] <= pc then lo = mid else hi = mid - 1 end
  end
  return SYM_NAME[addrs[lo]]
end
local count, total = {}, 0
local done = false
local function sample()
  local n = FRAME
  if n < P0 or done then return end
  if n >= P1 then
    done = true
    local t = {}
    for k, v in pairs(count) do t[#t + 1] = {k, v} end
    table.sort(t, function(a, b) return a[2] > b[2] end)
    local o = io.open("prof.log", "w")
    o:write(string.format("flips %d-%d samples %d\n", P0, P1, total))
    for i = 1, math.min(#t, tonumber(os.getenv("PROFN") or "80")) do o:write(string.format("%6d %5.1f%% %s\n", t[i][2], 100 * t[i][2] / total, t[i][1])) end
    o:close()
    M:exit()
    return
  end
  local pc = cpu.state["PC"].value
  local key
  if pc >= 0x8000 and pc < 0xC000 then
    key = string.format("b%d %s", mem:read_u8(S.S_BANK), near(pc))
  else
    key = near(pc)
  end
  count[key] = (count[key] or 0) + 1
  total = total + 1
end
local co = coroutine.create(function()
  while true do
    emu.wait(PERIOD)
    sample()
  end
end)
coroutine.resume(co)
