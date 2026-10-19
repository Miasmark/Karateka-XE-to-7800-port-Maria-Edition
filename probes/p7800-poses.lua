-- the fighters' poses (FINDINGS "The enemy's mirrored poses"): at each FRecP
-- (FRec recording a fighter drawn as objects), its lower pose $20, upper
-- pose $21, the enemy type $3E, $36, and whether it is the enemy (the
-- record's odd index: $2C bit 7); each distinct combination once with its
-- count, to poses.log at END. Runs playkey.lua unless NOPLAY.
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
local function zp(x) return mem:read_u8(ZM[x]) end
local END = tonumber(os.getenv("END") or "6000")
local seen = {}
local f = 0
T1 = mem:install_read_tap(S.FRecP, S.FRecP, "poses", function(a, d)
  if a ~= cpu.state["PC"].value then return d end
  local enemy = (zp(0x2C) & 0x80) ~= 0 and 1 or 0
  local k = string.format("%d %d %d %d %d", enemy, zp(0x20), zp(0x21), zp(0x3E), zp(0x36))
  seen[k] = (seen[k] or 0) + 1
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f == END then
    local o = io.open("poses.log", "w")
    for k, n in pairs(seen) do o:write(k .. " " .. n .. "\n") end
    o:close()
  end
end)
if not os.getenv("NOPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
