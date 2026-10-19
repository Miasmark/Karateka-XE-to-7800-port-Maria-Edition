-- (debug) where the CPU runs, frames PFROM to PTO: every opcode fetch in
-- $8000-$FFFF counted by its address (a read at the PC), the 40 busiest to
-- pchist.log, then MAME stops (the embrace's wait)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local h = {}
local f = 0
PCH_TAP = mem:install_read_tap(0x8000, 0xFFFF, "pch", function(ad, d)
  if f >= FROM and ad == cpu.state["PC"].value then h[ad] = (h[ad] or 0) + 1 end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f > TO then
    local t = {}
    for a, n in pairs(h) do t[#t + 1] = {a, n} end
    table.sort(t, function(x, y) return x[2] > y[2] end)
    local log = io.open("pchist.log", "w")
    for i = 1, math.min(40, #t) do log:write(string.format("%04X %d\n", t[i][1], t[i][2])) end
    log:close()
    M:exit()
  end
end)
