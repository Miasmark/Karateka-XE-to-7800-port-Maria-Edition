-- (debug) each entry of L1Add in frames PFROM-PTO (an opcode fetch): the
-- shape (L1_S, less the set's first L1_KB), its x (L1_X), the draw's image
-- (L1_SRC), the game's column $05 and shift $10, the blit's kind (L1B_KIND)
-- and the buffer, to l1add.log; MAME exits after PTO (FINDINGS "The
-- hardware test": the princess's leg)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FR = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local o = io.open("l1add.log", "w")
local f = 0
local function r(a) return mem:read_u8(a) end
LA_TAP = mem:install_read_tap(S.L1Add, S.L1Add, "l1a", function(ad, d)
  if f >= FR and f <= TO and ad == cpu.state["PC"].value then
    o:write(string.format("f%d shape %d x %d src $%02X%02X row %d col %d shift %d kind %d buf %d\n", f,
      (r(S.L1_S) - r(S.L1_KB)) & 0xFF, r(S.L1_X), r(S.L1_SRC + 1), r(S.L1_SRC), r(S.L1_ROW),
      r(S.G_Z05), r(S.G_Z10), r(S.L1B_KIND), r(S.L1_B)))
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f > TO then o:close(); M:exit() end
end)
