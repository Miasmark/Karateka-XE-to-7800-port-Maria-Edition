-- (debug) over a playback: from frame KFROM, the game's reads of the stick
-- (SWCHA $0280) and fire (INPT4 $0C) answered by this script instead (as
-- playkey.lua's INJECT): fire for KFIRE frames (the fighting stance), then
-- right held. For the princess's kick, which no run reaches (the user: walk
-- up to her in the fighting stance). ALSO: another probe (tmp-romuse.lua,
-- tmp-recsnap.lua)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("KFROM") or "25850")
local KFIRE = tonumber(os.getenv("KFIRE") or "6")
local KDIR = tonumber(os.getenv("KDIR") or "127", 10)      -- (SWCHA while walking: $7F right)
local kf = 0
KICK_T1 = mem:install_read_tap(0x0280, 0x0280, "kick_swcha", function(a, d)
  if kf < FROM then return d end
  if kf < FROM + KFIRE then return 0xFF end
  return (d & 0x0F) | (KDIR & 0xF0)
end)
KICK_T2 = mem:install_read_tap(0x000C, 0x000C, "kick_inpt4", function(a, d)
  if kf < FROM then return d end
  if kf < FROM + KFIRE then return d & 0x7F end
  return d | 0x80
end)
KICK_F = emu.register_frame_done(function() kf = kf + 1 end)
if os.getenv("ALSO") then dofile(os.getenv("PROBES") .. "/" .. os.getenv("ALSO")) end
