-- (debug) frames FR..FR+1: every CHBASE ($34) write with S_CHIX, S_NMICOUNT and
-- the PC, and each frame's end
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FR = tonumber(os.getenv("FR") or "1310")
local f = 0
local o = io.open("chlog.txt", "w")
TCH = mem:install_write_tap(0x34, 0x34, "chl", function(a, d)
  if f >= FR and f <= FR + 1 then
    o:write(string.format("f%d CHBASE %02X CHIX %d NMI %d PC %04X NMICHT %d\n", f, d, mem:read_u8(S.S_CHIX),
      mem:read_u8(S.S_NMICOUNT), cpu.state["PC"].value, mem:read_u8(S.S_NMICHT)))
  end
end)
TCX = mem:install_write_tap(S.S_CHIX, S.S_CHIX, "chx", function(a, d)
  if f >= FR and f <= FR + 1 then
    o:write(string.format("f%d   CHIX <- %d NMI %d PC %04X\n", f, d, mem:read_u8(S.S_NMICOUNT), cpu.state["PC"].value))
  end
end)
emu.register_frame_done(function()
  f = f + 1
  if f >= FR and f <= FR + 2 then o:write("--- frame end " .. f .. "\n"); o:flush() end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
