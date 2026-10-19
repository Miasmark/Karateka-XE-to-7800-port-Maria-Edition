-- reads of LO-HI (hex) after frame FROM, as the CPU's own (not an opcode
-- fetch elsewhere): by address with the first reader's PC and the count, to
-- ramreads.log at the end. For RAM that should be unused (a stale address
-- the linker didn't see). Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local LO, HI = tonumber(os.getenv("LO") or "7300", 16), tonumber(os.getenv("HI") or "79FF", 16)
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "6000")
local f, seen = 0, {}
TR = mem:install_read_tap(LO, HI, "rr", function(a, d)
  if f >= FROM then
    local e = seen[a]
    if e then e[2] = e[2] + 1 else seen[a] = {cpu.state["PC"].value, 1, f} end
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    local o = io.open("ramreads.log", "w")
    local ks = {}
    for a in pairs(seen) do ks[#ks + 1] = a end
    table.sort(ks)
    for _, a in ipairs(ks) do o:write(string.format("%04X PC %04X x%d first frame %d\n", a, seen[a][1], seen[a][2], seen[a][3])) end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
