-- every writer of LO-HI (p7800-ramreaders.lua for writes) (hex) after frame FROM (p7800-ramreads.lua keeps
-- only an address's first): by the reading PC, its lowest and highest
-- address, how many addresses, its first and last frame, and the scene ($D0's
-- 7800 home, through the zero-page map) at the first, to ramwriters.log at the
-- end. MARIA's reads come with whatever PC the CPU was halted at. Runs
-- playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local LO, HI = tonumber(os.getenv("LO") or "1B80", 16), tonumber(os.getenv("HI") or "1DF5", 16)
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "6000")
local f, by = 0, {}
TR = mem:install_write_tap(LO, HI, "rws", function(a, d)
  if f >= FROM then
    local pc = cpu.state["PC"].value
    local e = by[pc]
    if not e then
      e = { lo = a, hi = a, n = 0, seen = {}, f0 = f, f1 = f, sc = ZMAP and mem:read_u8(ZMAP[0xD0]) or -1 }
      by[pc] = e
    end
    if not e.seen[a] then e.seen[a] = true; e.n = e.n + 1 end
    if a < e.lo then e.lo = a end
    if a > e.hi then e.hi = a end
    e.f1 = f
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    local o = io.open("ramwriters.log", "w")
    local pcs = {}
    for pc in pairs(by) do pcs[#pcs + 1] = pc end
    table.sort(pcs)
    for _, pc in ipairs(pcs) do
      local e = by[pc]
      o:write(string.format("PC %04X  $%04X-$%04X  %4d addrs  frames %d-%d  scene %d\n",
        pc, e.lo, e.hi, e.n, e.f0, e.f1, e.sc))
    end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
