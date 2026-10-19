-- the hit stars recorded (FINDINGS "The hit stars as objects"): each StarM
-- with objects on (StarM1): the flip, buffer $07, the image ($04: $93 big,
-- $94 small), row ($06 - 35), column ($05), shift ($10), to starlog.log.
-- Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local o = io.open("starlog.log", "w")
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local function zp(x) return mem:read_u8(ZM[x]) end
T1 = mem:install_read_tap(S.StarM1, S.StarM1, "sl1", function(a, d)
  if a == cpu.state["PC"].value then
    o:write(string.format("flip %d $07=%02X %s row %d col %d shift %d\n", PLAYKEY_N or 0, zp(7),
      zp(4) == 0x93 and "big" or "small", (zp(6) - 35) & 0xFF, zp(5), zp(0x10)))
    o:flush()
  end
  return d end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
