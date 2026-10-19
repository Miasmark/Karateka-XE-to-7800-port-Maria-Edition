-- the fighters' runtime tables at the scripted player's flip AT (FINDINGS
-- "The fighters as objects: step 3"): each buffer's front boxes (FG_*, as
-- shown; FGR_*, as recorded), fighter objects (FO_*) and band zones (ZT_*),
-- to ftdump.log. Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local AT = tonumber(os.getenv("AT") or "366")
local done = false
local function b(a) return mem:read_u8(a) end
emu.register_frame_done(function()
  if done or (PLAYKEY_N or 0) < AT then return end
  done = true
  local o = io.open("ftdump.log", "w")
  o:write(string.format("flip %d, $07 %02X\n", PLAYKEY_N, b(SYM_ADDR.S_FBUF ~= nil and 0 or 0)))
  for buf = 0, 1 do
    o:write(string.format("buffer %s: front boxes shown %d, recorded %d, fighters seen %d\n", buf == 0 and "A" or "B",
      b(S.FG_NS + buf), b(S.FGR_N + buf), b(S.FT_SEEN + buf)))
    for i = 0, b(S.FG_NS + buf) - 1 do
      local k = buf * 8 + i
      o:write(string.format("  shown box cols %d+%d rows %d-%d\n", b(S.FG_C0 + k), b(S.FG_W + k), b(S.FG_R0 + k), b(S.FG_R1 + k)))
    end
    for i = 0, b(S.FGR_N + buf) - 1 do
      local k = buf * 8 + i
      o:write(string.format("  recorded box cols %d+%d rows %d-%d\n", b(S.FGR_C0 + k), b(S.FGR_W + k), b(S.FGR_R0 + k), b(S.FGR_R1 + k)))
    end
    o:write(string.format("  objects %d\n", b(S.S_FON + buf)))
    for i = 0, b(S.S_FON + buf) - 1 do
      local k = buf * (S.FT_FON or 40) + i
      o:write(string.format("    cell %d x %d pw %02X lo %d\n", b(S.FO_CELL + k), b(S.FO_X + k), b(S.FO_PW + k), b(S.FO_LO + k)))
    end
    o:write(string.format("  band zones %d\n", b(S.S_ZTN + buf)))
    for i = 0, b(S.S_ZTN + buf) - 1 do
      local k = buf * 16 + i
      o:write(string.format("    dll %02X cell %d s %d h %d bitmap %02X%02X\n", b(S.ZT_DLL + k), b(S.ZT_CELL + k),
        (b(S.ZT_H + k) >> 4) & 7, b(S.ZT_H + k) & 15, b(S.ZT_BHI + k), b(S.ZT_BLO + k)))
    end
  end
  o:close()
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
