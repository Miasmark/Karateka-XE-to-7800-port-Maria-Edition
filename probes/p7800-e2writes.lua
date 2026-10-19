-- writes into engine part 2's RAM copy ($7300-$7FFF) after FROM frames (the
-- load's copy first), by address with the first writer's PC and the count,
-- to e2writes.log at the end. Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("FROM") or "600")
local END = tonumber(os.getenv("END") or "6000")
local f, seen = 0, {}
TW = mem:install_write_tap(0x7300, 0x7FFF, "e2w", function(a, d)
  if f >= FROM then
    local e = seen[a]
    if e then e[2] = e[2] + 1 else seen[a] = {cpu.state["PC"].value, 1} end
  end
end)
emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    local o = io.open("e2writes.log", "w")
    local ks = {}
    for a in pairs(seen) do ks[#ks + 1] = a end
    table.sort(ks)
    for _, a in ipairs(ks) do o:write(string.format("%04X %04X %d\n", a, seen[a][1], seen[a][2])) end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
