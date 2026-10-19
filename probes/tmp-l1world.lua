-- (debug) p7800-stateplay.lua's companion (SPALSO): at each flip, both
-- buffers' level-1 world (L1_WLD) and view (L1_V), the buffer drawn ($07),
-- $4C and $E9, to l1world.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local o = io.open("l1world.log", "w")
local last = -1
TLW = mem:install_read_tap(S.TopFlip, S.TopFlip, "l1w", function(a, d)
  if _G.PROBE_PEEK or a ~= cpu.state["PC"].value then return d end
  local n = _G.STATEPLAY_N or 0
  if n == last then return d end
  last = n
  local function v(b) return mem:read_u8(S.L1_V + 2 * b) + 256 * mem:read_u8(S.L1_V + 2 * b + 1) end
  o:write(string.format("%d drawn %s W %d %d V %d %d 4C %d E9 %d S_L1 %d\n", n,
    mem:read_u8(ZM[7]) == 0x20 and "B" or "A", mem:read_u8(S.L1_WLD), mem:read_u8(S.L1_WLD + 1), v(0), v(1),
    mem:read_u8(ZM[0x4C]), mem:read_u8(ZM[0xE9]), mem:read_u8(S.S_L1)))
  o:flush()
  return d
end)
