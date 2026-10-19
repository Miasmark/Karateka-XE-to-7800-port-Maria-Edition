-- (debug) every write to MARIA's BACKGRND ($20) and P0C2 ($22) in frames
-- FROM-TO: frame, the value, PC, and the time into the frame (us), to
-- bgwrites.log, with the game's scheme (G_L0F0C), S_SKY and HOLD_N at each
-- frame's start; MAME exits after TO. SYM: the build's symbol file.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FR = tonumber(os.getenv("BFROM") or "0")
local TO = tonumber(os.getenv("BTO") or "100")
local o = io.open("bgwrites.log", "w")
local f, t0 = 0, 0
BG_TAP = mem:install_write_tap(0x20, 0x3F, "bg", function(a, d)
  if f >= FR and f <= TO and (a % 4 ~= 0 or a == 0x20) and a ~= 0x24 and a ~= 0x2C and a ~= 0x30 and a ~= 0x34 and a ~= 0x38 and a ~= 0x3C then
    local us = (M.time:as_double() - t0) * 1e6
    o:write(string.format("f%d %s=%02X pc $%04X t %5.0f\n", f, a == 0x20 and "BG" or string.format("$%02X", a), d, cpu.state["PC"].value, us))
  end
end)
emu.register_frame_done(function()
  f = f + 1
  t0 = M.time:as_double()
  if f >= FR and f <= TO then
    o:write(string.format("-- f%d starts: sch %d sky %02X hold %d\n", f, mem:read_u8(S.G_L0F0C), mem:read_u8(S.S_SKY),
      S.HOLD_N and mem:read_u8(S.HOLD_N) or -1))
  end
  if f >= FR and f <= TO then M.video:snapshot() end
  if f > TO then o:close(); M:exit() end
end)
