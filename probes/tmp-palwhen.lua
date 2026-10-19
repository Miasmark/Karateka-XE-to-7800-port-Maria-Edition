-- (debug) a companion of p7800-stateplay.lua (SPALSO): from flip WFROM to
-- WTO, each write to palette 1's colour 1 ($25) with the NMI count, the
-- line after the vertical blank NMI (by machine time, as tmp-dlimargin.lua)
-- and the PC, a line a frame, to palwhen.log (FINDINGS "The flickering
-- arrows": where the status bar's colours land against the floor's last
-- line)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local F0, F1 = tonumber(os.getenv("WFROM") or "0"), tonumber(os.getenv("WTO") or "0")
local log = io.open("palwhen.log", "w")
local LINE = 1 / (59.92 * 263)
local t0 = nil
local seq = {}
local function on()
  local f = _G.STATEPLAY_N or -1
  return f >= F0 and f <= F1
end
PWH_V = mem:install_read_tap(S.NmiVbi, S.NmiVbi, "pwhv", function(ad, d)
  if cpu.state["PC"].value == S.NmiVbi then t0 = M.time:as_double() end
  return d
end)
PWH_W = mem:install_write_tap(tonumber(os.getenv("PWLO") or "37"), tonumber(os.getenv("PWHI") or "37"), "pwhw", function(ad, d)
  if on() and t0 then
    seq[#seq + 1] = string.format("%d:$%02X=%02X@%.2f/%04X", mem:read_u8(S.S_NMICOUNT), ad, d,
      (M.time:as_double() - t0) / LINE, cpu.state["PC"].value)
  end
  return d
end)
emu.register_frame_done(function()
  if on() then log:write(string.format("n%d %s\n", _G.STATEPLAY_N or -1, table.concat(seq, " "))); log:flush() end
  seq = {}
end)
