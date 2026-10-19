-- who marks a buffer's top changed (TopStale, in the art bank) from FROM to
-- END: the caller (the JSR's address) and the frame, to topstale.log.
-- WITHPLAY: playkey.lua's input as well.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local function pc() return cpu.state["PC"].value end
local f, cnt, o = 0, {}, io.open("topstale.log", "w")
-- the label at or below an address
local labels = {}
for name, a in pairs(S) do if a >= 0xA000 and a < 0xC000 then labels[#labels + 1] = {a, name} end end
table.sort(labels, function(x, y) return x[1] < y[1] end)
local function near(a)
  local best = "?"
  for _, l in ipairs(labels) do if l[1] <= a then best = l[2] .. string.format("+%d", a - l[1]) else break end end
  return best
end
T = mem:install_read_tap(S.TopStale, S.TopStale, "ts", function(a, d)
  if a == pc() and f >= FROM and mem:read_u8(S.S_BANK) == 6 then
    local sp = cpu.state["SP"].value
    local ret = mem:read_u8(0x100 + ((sp + 1) & 0xFF)) + 256 * mem:read_u8(0x100 + ((sp + 2) & 0xFF))
    local k = near(ret - 2)
    cnt[k] = (cnt[k] or 0) + 1
    o:write(string.format("f%d %s buf %d\n", f, k, mem:read_u8(S.S_TBUF)))
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then
    for k, n in pairs(cnt) do o:write(string.format("%s: %d\n", k, n)) end
    o:close(); M:exit()
  end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
