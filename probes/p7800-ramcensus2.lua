-- the RAM census by mode (FINDINGS "The RAM census: gameplay against the
-- rest"): for console RAM ($1800-$27FF) and cart RAM ($4000-$7FFF), after
-- the boot's clear, which addresses are written in gameplay (the scene page
-- in S_SCENEBANK is level 1's, 2's, 3's or the finale's: banks 1-4), which
-- outside it (the title, story, intro cutscene and attract demo: bank 0;
-- and the boot), and (READS=lo-hi,...) which gameplay reads (not counting instruction
-- fetches, nor the clear loop's dummy reads; other indexed stores' dummy
-- reads count, which only errs safe). To ramcensus2.log every 200 frames
-- and at END: "G", "N", "R" bitmaps, 64 hex digits a page line, as
-- p7800-ramcensus.lua. WITHPLAY=1: playkey.lua drives; ALSO: another probe.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local c0, c1 = S.ClrRam, S.ClrCart + 16
local END = tonumber(os.getenv("END") or "300")
local G, N, R = {}, {}, {}
local booted, f = false, 0
local function pc() return cpu.state["PC"].value end
local function play() local b = mem:read_u8(S.S_SCENEBANK); return b >= 1 and b <= 4 end
CT = {}
for _, r in ipairs({{0x1800, 0x27FF}, {0x4000, 0x7FFF}}) do
  CT[#CT + 1] = mem:install_write_tap(r[1], r[2], "cw" .. r[1], function(a, d)
    local p = pc()
    if p >= c0 and p < c1 then booted = true
    elseif booted then if play() then G[a] = true else N[a] = true end end
    return d end)
end
-- reads only where READS says (hex ranges lo-hi,...): read taps on all of RAM
-- ran at about 1/100 speed
for lo, hi in (os.getenv("READS") or ""):gmatch("(%x+)-(%x+)") do
  CT[#CT + 1] = mem:install_read_tap(tonumber(lo, 16), tonumber(hi, 16), "cr" .. lo, function(a, d)
    local p = pc()
    if booted and a ~= p and not (p >= c0 and p < c1) and play() then R[a] = true end
    return d end)
end
local function dump()
  local o = io.open("ramcensus2.log", "w")
  for _, set in ipairs({{"G", G}, {"N", N}, {"R", R}}) do
    for page = 0x18, 0x7F do
      if page < 0x28 or page >= 0x40 then
        local t = {}
        for i = 0, 255, 4 do
          local v = 0
          for k = 0, 3 do if set[2][page * 256 + i + k] then v = v + (8 >> k) end end
          t[#t + 1] = string.format("%X", v)
        end
        o:write(string.format("%s %02X %s\n", set[1], page, table.concat(t)))
      end
    end
  end
  o:write(string.format("frame %d\n", f))
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if f % 200 == 0 then dump() end
  if f >= END then dump(); M:exit() end
end)
if os.getenv("ALSO") then dofile(os.getenv("PROBES") .. "/" .. os.getenv("ALSO"))
elseif os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
