-- a snapshot every frame from FROM to END (then exit), for comparing two
-- builds' pictures. Frames count from the cartridge's first instruction
-- (Reset), not from power-on: the BIOS's signature check takes a time that
-- depends on the ROM, so two builds' power-on frames don't line up (and
-- MAME's a7800 has no BIOS to skip: -listbios gives only the retail and the
-- prototype ones). RAW=1: count from power-on instead.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local f = os.getenv("RAW") and 0 or nil
local RESET = SYM_ADDR.Reset
T = mem:install_read_tap(RESET, RESET, "rst", function(a, d)
  if f == nil and a == cpu.state["PC"].value then f = 0 end
  return d end)
emu.register_frame_done(function()
  if f == nil then return end
  f = f + 1
  if f >= FROM then M.video:snapshot() end
  if f >= END then M:exit() end
end)
