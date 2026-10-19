-- (debug) the CPU's writes to cart RAM ($4000-$7FFF) by phase: per 100
-- frames, per page, the writes and the writing PCs (up to 4), to
-- cramph.log at each 500th frame and END. Runs playkey.lua (its env applies).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local c0, c1 = S.ClrRam, S.ClrCart + 16
local END = tonumber(os.getenv("END") or "6000")
local f, booted = 0, false
local rec = {}            -- [bucket][page] = {n, pcs{}}
TCP = mem:install_write_tap(0x4000, 0x7FFF, "cph", function(a, d)
  local pc = cpu.state["PC"].value
  if pc >= c0 and pc < c1 then booted = true; return end
  if not booted then return end
  local b = f // 100
  local t = rec[b]
  if not t then t = {}; rec[b] = t end
  local p = a >> 8
  local r = t[p]
  if not r then r = {0, {}, 0}; t[p] = r end
  r[1] = r[1] + 1
  if not r[2][pc] and r[3] < 4 then r[2][pc] = true; r[3] = r[3] + 1 end
end)
local function dump()
  local o = io.open("cramph.log", "w")
  local bs = {}
  for b in pairs(rec) do bs[#bs + 1] = b end
  table.sort(bs)
  for _, b in ipairs(bs) do
    local ps = {}
    for p in pairs(rec[b]) do ps[#ps + 1] = p end
    table.sort(ps)
    for _, p in ipairs(ps) do
      local r = rec[b][p]
      local pcs = {}
      for k in pairs(r[2]) do pcs[#pcs + 1] = string.format("%04X", k) end
      o:write(string.format("%d %02X %d %s\n", b * 100, p, r[1], table.concat(pcs, ",")))
    end
  end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if f % 500 == 0 or f == END then dump() end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
