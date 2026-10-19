-- each FtPlain call (the fighters' plain parts: FINDINGS "The fighters as
-- objects: step 3") between the scripted player's flips AT-2 and AT: the
-- image's address and bank, its row, column, mirroring, palette, and the
-- objects made before and after (S_FON), to ftplain.log. Runs playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local AT = tonumber(os.getenv("AT") or "298")
local o = io.open("ftplain.log", "w")
local function b(a) return mem:read_u8(a) end
local function on() local n = PLAYKEY_N or 0; return n >= AT - 2 and n <= AT end
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
T1 = mem:install_read_tap(S.FtPlain, S.FtPlain, "fp1", function(a, d)
  if a == cpu.state["PC"].value and b(S.S_BANK) == 5 and on() then
    o:write(string.format("flip %d buf %d plain $%02X%02X bank %d row %d col %d mir %02X pal %02X uy %d objects %d,%d cols %d\n",
      PLAYKEY_N, b(S.S_FBUF), b(ZM[1]), b(ZM[0]), b(S.FT_SRCB), b(S.FP_ROW), b(S.FP_COL), b(S.S_FMIR), b(S.S_FPAL),
      b(S.FP_UY), b(S.S_FON), b(S.S_FON + 1), b(S.S_FCOL)))
  end
  return d end)
T2 = mem:install_read_tap(S.FtUpper, S.FtUpper, "fp2", function(a, d)
  if a == cpu.state["PC"].value and b(S.S_BANK) == 5 and on() then
    o:write(string.format("flip %d FtUpper X=%d\n", PLAYKEY_N, cpu.state["X"].value))
  end
  return d end)
emu.register_frame_done(function() o:flush() end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
