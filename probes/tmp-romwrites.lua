-- (debug) the CPU's writes to $4000-$7FFF (V2: bank 6, ROM: a write there
-- is lost; v1's cart RAM), by PC and address range, from frame WFROM (after
-- the boot's clear) to END, to romwrites.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local F0 = tonumber(os.getenv("WFROM") or "120")
local END = tonumber(os.getenv("END") or "6000")
local f, by = 0, {}
ROMW_TAP = mem:install_write_tap(0x4000, 0x7FFF, "romw", function(a, d)
  if f < F0 then return end
  local pc = cpu.state["PC"].value
  local e = by[pc]
  if not e then e = {n = 0, lo = a, hi = a, f = f}; by[pc] = e end
  e.n = e.n + 1
  if a < e.lo then e.lo = a end
  if a > e.hi then e.hi = a end
end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then
    local o = io.open("romwrites.log", "w")
    for pc, e in pairs(by) do
      o:write(string.format("PC $%04X: %d writes $%04X-$%04X, first at frame %d\n", pc, e.n, e.lo, e.hi, e.f))
    end
    o:close()
    M:exit()
  end
end)
