-- each list build's top zones (TopEmit, in the art bank: S_ARG the first
-- row, S_H the rows, and whether it got a slot), the distinct sets to
-- topzones.log. WITHPLAY: playkey.lua's input as well.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "300")
local function pc() return cpu.state["PC"].value end
local cur, seen, order, f, inb = {}, {}, {}, 0, false
T1 = mem:install_read_tap(S.TopEmit, S.TopEmit, "tz1", function(a, d)
  if a == pc() and inb and mem:read_u8(S.S_BANK) == 6 then
    cur[#cur + 1] = string.format("%d+%d", mem:read_u8(S.S_ARG), mem:read_u8(S.S_H))
  end
  return d end)
local function fin(a, d)
  if a == pc() and inb then
    inb = false
    if #cur > 0 then local k = table.concat(cur, " "); if not seen[k] then seen[k] = 0; order[#order + 1] = k end; seen[k] = seen[k] + 1 end
    cur = {}
  end
  return d end
T2 = mem:install_read_tap(S.BuildDll, S.BuildDll, "tz2", function(a, d) if a == pc() then inb = true; cur = {} end; return d end)
T3 = mem:install_read_tap(S.FrameShowA, S.FrameShowA, "tz3", fin)
T4 = mem:install_read_tap(S.FrameShowB, S.FrameShowB, "tz4", fin)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then
    local o = io.open("topzones.log", "w")
    for _, k in ipairs(order) do o:write(string.format("%4d x  %s\n", seen[k], k)) end
    o:close(); M:exit()
  end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
