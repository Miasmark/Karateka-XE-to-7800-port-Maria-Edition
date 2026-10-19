-- every blit's parameters from frame FROM to END, in order: the entry (A,
-- AR, M, MR: the blitter's entries from the build's symbols, G_L284E and
-- its fixed offsets), $03/$04 the image, $05 column, $06 top line, $0F mode,
-- $10 shift, $07 buffer, to blitparams.log ("frame kind src col top mode
-- shift buf"); to compare two builds' drawing. Runs playkey.lua (its env
-- applies).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "6000")
local ZP = {}
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZP[tonumber(z, 16)] = tonumber(t, 16) end
end
local function z(n) return mem:read_u8(ZP[n]) end
local base = S.G_L284E - 0x284E           -- (engine part 2's blitter module: one delta)
local ENTRY = {[0x284E] = "A", [0x29C2] = "AR", [0x2B82] = "M", [0x2B8B] = "MR"}
local o = io.open("blitparams.log", "w")
local f = 0
TAPS = {}
for xa, k in pairs(ENTRY) do
  TAPS[#TAPS + 1] = mem:install_read_tap(base + xa, base + xa, "bp" .. k, function(a, d)
    if f >= FROM and a == PCs.value then
      o:write(string.format("%d %s %02X%02X %d %d %d %d %02X\n", f, k, z(0x04), z(0x03), z(0x05), z(0x06),
        z(0x0F), z(0x10), z(0x07)))
    end
    return d end)
end
emu.register_frame_done(function()
  f = f + 1
  if f >= END then o:close(); M:exit() end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
