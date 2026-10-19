-- the floor's blits (FINDINGS "The floor as tiles"): each FlBlitP (set-up)
-- and FlBlitEnd with the frame, flip, the blit's first row ($06 - 35), rows
-- ($0D), FL_FROW and FL_MIR; and at each frame's end whether blitter A's
-- step is still patched (the byte at its 7800 address PATCH, hex: $4C) and
-- the PC; the first LIMIT events, to floorblit.log. Runs playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local function zp(x) return mem:read_u8(ZM[x]) end
local PATCH = tonumber(os.getenv("PATCH"), 16)
local LIMIT = tonumber(os.getenv("LIMIT") or "400")
local o = io.open("floorblit.log", "w")
local f, n = 0, 0
local function log(s) if n < LIMIT then n = n + 1; o:write(s .. "\n"); o:flush() end end
local function bank() return mem:read_u8(S.S_BANK) end
TFB1 = mem:install_read_tap(S.FlBlitP, S.FlBlitP, "fb1", function(a, d)
  if a == cpu.state["PC"].value and bank() == 5 then
    log(string.format("f%d flip %s setup row %d rows %d frow %d src %02X%02X mode %02X col1E %d w0E %d ret %02X%02X", f, tostring(PLAYKEY_N),
      zp(6) - 35, zp(0x0D), mem:read_u8(S.FL_FROW), zp(4), zp(3), zp(0x0F), zp(0x1E), zp(0x0E), mem:read_u8(S.FL_RETH), mem:read_u8(S.FL_RETL)))
  end
  return d end)
TFB2 = mem:install_read_tap(S.FlBlitEnd, S.FlBlitEnd, "fb2", function(a, d)
  if a == cpu.state["PC"].value then
    log(string.format("f%d end frow %d mir %d", f, mem:read_u8(S.FL_FROW), mem:read_u8(S.FL_MIR)))
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if os.getenv("PATCHLOG") and mem:read_u8(PATCH) == 0x4C then
    log(string.format("f%d frame end: still patched, PC %04X, FL_BLIT %02X", f, cpu.state["PC"].value, mem:read_u8(S.FL_BLIT)))
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
