-- (debug) every blit AkCap records (Akuma's, FT_IN 2; level 3's hawk, FT_IN
-- 3): the picture (STATEPLAY_N), the image ($03/$04), flags (S_BTX: bit 7
-- mirrored, 6 right-aligned, 5 a mask, 4 the hawk's), column $05, row $06 -
-- 35, shift $10, the scene ($D0's), to aklog.log. A replay's companion.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local o = io.open("aklog.log", "w")
TAK = mem:install_read_tap(sym.AkCapB1, sym.AkCapB1, "akl", function(a, d)
  if a ~= cpu.state["PC"].value then return end
  local r = function(x) return mem:read_u8(x) end
  o:write(string.format("%d %02X%02X %02X %d %d %d\n", _G.STATEPLAY_N or -1, r(sym.G_Z04), r(sym.G_Z03), r(sym.S_BTX),
    r(sym.G_Z05), (r(sym.G_Z06) - 0x23) & 0xFF, r(sym.G_Z10)))
end)
