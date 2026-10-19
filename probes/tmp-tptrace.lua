-- (debug) TpPlace's outcomes: its tries (entry), its places (TpPlF) and its
-- failures (TpPlNo), and TopEmitNone's entries with a list counted, in play;
-- the first 40 events of the first frame with a failure. To tptrace.log.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local function r(a) return mem:read_u8(a) end
local f, c, ev, ff = 0, {try = 0, place = 0, fail = 0, none = 0}, {}, nil
local function tap(pc, name, b1, fn)
  return mem:install_read_tap(pc, pc, name, function(a, d)
    if a == cpu.state["PC"].value and r(pc + 1) == b1 then fn() end
    return d
  end)
end
local cur, ntry, kept = {}, 0, nil
ALL = {}
local function log(s)
  cur[#cur + 1] = "f" .. f .. " " .. s
  if #ALL < 6000 then ALL[#ALL + 1] = "f" .. f .. " " .. s end
  if s:sub(1, 3) == "try" then ntry = ntry + 1 end
end
A = tap(S.TpPlace, "a", S.S_BLPC & 0xFF, function() c.try = c.try + 1; local t = {}
  for k = 0, 4 do t[#t + 1] = string.format("%04X", r(S.TP_SGP + 2 * k) + 256 * r(S.TP_SGP + 2 * k + 1)) end
  log("try " .. (r(S.S_EW) + 2) .. " row " .. r(S.TP_SG) .. " ptrs " .. table.concat(t, " ")) end)
B = tap(S.TpPlF, "b", S.TP_SGP & 0xFF, function() c.place = c.place + 1; log("place") end)
C = tap(S.TpPlNo, "c", 0x60, function() c.fail = c.fail + 1; if ff == nil then ff = f end; log("FAIL") end)
D = tap(S.TopSegStart, "d", 0xAD, function() log("reset") end)
emu.register_frame_done(function()
  f = f + 1
  if ntry >= 5 and not kept then kept = cur end
  cur, ntry = {}, 0
  if f % 1000 == 0 then
    local o = io.open("tptrace.log", "w")
    o:write(string.format("tries %d places %d fails %d\n", c.try, c.place, c.fail))
    for _, s in ipairs(ALL) do o:write(s .. "\n") end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
