-- (debug) how full the CPU's tables get: at each frame's end, each buffer's
-- fighter objects (S_FON, of FT_FON), level 1's objects (L1_N, of L1_NMAX),
-- top entries (TOPLN, of TOPL_MAX); and the frames with Akuma's pose search
-- on (AKP_ON). In play only (not under the blank list, nor the text). The largest of each, to tabmax.log at each 1000th frame.
-- Runs playkey.lua; the no-rules MAME (cart RAM).
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local function r(a) return mem:read_u8(a) end
local mx = {fon = 0, l1n = 0, topln = 0}
local f, akp = 0, 0
local reg = {[0x2C] = 0, [0x30] = 0}
TREG = mem:install_write_tap(0x2C, 0x30, "tm_reg", function(a, d) if reg[a] then reg[a] = d end end)
emu.register_frame_done(function()
  f = f + 1
  local play = reg[0x2C] * 256 + reg[0x30] ~= S.BLANK_DLL and r(S.S_STORY) == 0 and r(S.S_TITLEA) == 0
    and r(S.S_TITLEB) == 0
  if play then
  for b = 0, 1 do
    mx.fon = math.max(mx.fon, r(S.S_FON + b))
    mx.l1n = math.max(mx.l1n, r(S.L1_N + b))
    mx.topln = math.max(mx.topln, r(S.TOPLN + b))
  end
  if r(S.AKP_ON) ~= 0 then akp = akp + 1 end
  end
  if f % 1000 == 0 then
    local o = io.open("tabmax.log", "w")
    o:write(string.format("fighter objects %d, level objects %d, top entries %d; Akuma's search on %d frames\n",
      mx.fon, mx.l1n, mx.topln, akp))
    o:close()
  end
end)
if not os.getenv("PLAYBACK") then dofile(os.getenv("PROBES") .. "/playkey.lua") end   -- (under port/replay.sh: the recording plays)
