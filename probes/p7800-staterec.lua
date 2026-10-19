-- the game's state at each flip (FINDINGS "Replaying a recording on another
-- build"): at each entry of TopFlip (every flip: $0862's, $B60F's) once play has
-- started ($D0 not 0), the bytes at the addresses in STATE
-- (probes/gamestate.py's work/gamestate.txt), one record a flip, to
-- state.bin; with SNAPF (comma list of those flips) a snapshot of each one's
-- picture (as playkey.lua's SNAPDL: the end of the first frame showing it).
-- For a recording played back on the cartridge it was made with. Stops at
-- END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "30000")
local addrs = {}
for l in io.lines(os.getenv("STATE")) do addrs[#addrs + 1] = tonumber(l, 16) end
local snapf = {}
for t in (os.getenv("SNAPF") or ""):gmatch("%d+") do snapf[tonumber(t)] = true end
ANYSCENE = os.getenv("ANYSCENE") ~= nil      -- (ANYSCENE=1: scene 0 too, the attract loop: $D0 0)
local o = io.open("state.bin", "wb")
local fl = io.open("flips.txt", "w")      -- each flip's frame
local n, f = 0, 0
local dpp, at, wait, due = {[0x2C] = 0, [0x30] = 0}, nil, false, false
TW = mem:install_write_tap(0x2C, 0x30, "srd", function(a, d)
  if a ~= 0x2C and a ~= 0x30 then return end
  dpp[a] = d
  if wait and dpp[0x2C] * 256 + dpp[0x30] ~= at then wait = false; due = true end
end)
T1 = mem:install_read_tap(S.TopFlip, S.TopFlip, "sr1", function(a, d)
  if a ~= cpu.state["PC"].value or (mem:read_u8(0xD0) == 0 and not ANYSCENE) then return d end
  n = n + 1
  local t = {}
  for i = 1, #addrs do t[i] = string.char(mem:read_u8(addrs[i])) end
  o:write(table.concat(t))
  fl:write(string.format("%d %d\n", n, f))
  if snapf[n] then wait = true; at = dpp[0x2C] * 256 + dpp[0x30] end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if due then due = false; M.video:snapshot() end
  if f >= END then
    o:close()
    fl:close()
    local l = io.open("staterec.log", "w")
    l:write(string.format("%d flips of %d bytes\n", n, #addrs))
    l:close()
    M:exit()
  end
end)
