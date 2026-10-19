-- (debug) each entry of L1Find in frames PFROM-PTO: the image (L1_SRC), row
-- (L1_ROW), flags (L1_FLM) and the set (L1_SET), and on its way out (the RTS
-- after L1FindNo or the SEC: by C) whether it found one, to l1find.log; MAME
-- exits after PTO. SYM: the build's symbol file.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FR = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local o = io.open("l1find.log", "w")
local f = 0
local function r(a) return mem:read_u8(a) end
LF_TAP = mem:install_read_tap(S.L1Find, S.L1Find, "l1f", function(ad, d)
  if f >= FR and f <= TO and ad == cpu.state["PC"].value then
    o:write(string.format("f%d src $%02X%02X row %d flm %02X set %d\n", f, r(S.L1_SRC + 1), r(S.L1_SRC), r(S.L1_ROW),
      r(S.L1_FLM), r(S.L1_SET)))
  end
  return d
end)
LF_NO = mem:install_read_tap(S.L1FindNo, S.L1FindNo, "l1fn", function(ad, d)
  if f >= FR and f <= TO and ad == cpu.state["PC"].value then o:write("   not found\n") end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f > TO then o:close(); M:exit() end
end)
