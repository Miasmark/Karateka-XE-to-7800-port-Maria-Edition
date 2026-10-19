-- (debug) a companion of p7800-stateplay.lua (SPALSO): each entry to the
-- address SONGPC (hex: the game's $0C66 as relocated in this build) in frames
-- PFROM to PTO: frame, flip, A, X, Y, the caller (the stack's return) and the
-- song table's entry it reads, to songcall.log; MAME exits after PTO
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FR = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local PC = tonumber(os.getenv("SONGPC") or "9C66", 16)
local TAB = tonumber(os.getenv("SONGTAB") or "9D03", 16)
local o = io.open("songcall.log", "w")
local f = 0
local function r(a) return mem:read_u8(a) end
SC_TAP = mem:install_read_tap(PC, PC, "songcall", function(ad, d)
  if f >= FR and f <= TO and ad == cpu.state["PC"].value then
    local a = cpu.state["A"].value
    local sp = cpu.state["SP"].value & 0xFF
    local ret = r(0x100 + ((sp + 1) & 0xFF)) + 256 * r(0x100 + ((sp + 2) & 0xFF)) + 1
    local p = r(TAB + 2 * a) + 256 * r(TAB + 2 * a + 1)
    o:write(string.format("f%d n%d A %02X X %02X Y %02X from %04X ptr %04X first %02X\n", f, _G.STATEPLAY_N or -1,
      a, cpu.state["X"].value, cpu.state["Y"].value, ret, p, r(p)))
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f > TO then o:close(); M:exit() end
end)
