-- (debug) each entry of L1Fill in frames PFROM-PTO (an opcode fetch): the
-- game's fill columns ($05-$09), rows ($06-$08), the pattern flag and
-- S_NOFILL, to l1fill.log; MAME exits after PTO (FINDINGS "The hardware
-- test": the princess's leg)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FR = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local o = io.open("l1fill.log", "w")
local f = 0
local function r(a) return mem:read_u8(a) end
LFL_TAP = mem:install_read_tap(S.L1Fill, S.L1Fill, "l1fl", function(ad, d)
  if f >= FR and f <= TO and ad == cpu.state["PC"].value then
    o:write(string.format("f%d cols %d-%d rows %d-%d pat %d nofill %d buf $%02X\n", f, r(S.G_Z05), r(S.G_Z09),
      r(S.G_Z06), r(S.G_Z08), r(S.L1F_PAT), r(S.S_NOFILL), r(S.G_Z07)))
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f > TO then o:close(); M:exit() end
end)
