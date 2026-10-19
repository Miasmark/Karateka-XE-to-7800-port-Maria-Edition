-- writes aimed at the fixed bank's addresses LO-HI (hex; default $F800-$FEFF:
-- engine part 2's read-only modules), from frame 0: in ROM they are lost, so
-- any is a bug. By address, with the first writer's PC and the count, to
-- romwrites.log at the end. Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local LO, HI = tonumber(os.getenv("LO") or "F800", 16), tonumber(os.getenv("HI") or "FEFF", 16)
local END = tonumber(os.getenv("END") or "6000")
local f, seen = 0, {}
TW = mem:install_write_tap(LO, HI, "romw", function(a, d)
  local e = seen[a]
  if e then e[2] = e[2] + 1 else seen[a] = {cpu.state["PC"].value, 1, f} end
end)
emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    local o = io.open("romwrites.log", "w")
    local ks = {}
    for a in pairs(seen) do ks[#ks + 1] = a end
    table.sort(ks)
    for _, a in ipairs(ks) do o:write(string.format("%04X PC %04X x%d first frame %d\n", a, seen[a][1], seen[a][2], seen[a][3])) end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
