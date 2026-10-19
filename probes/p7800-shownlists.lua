-- the band zones' lists MARIA is given (FINDINGS "The fighters as objects:
-- step 4"): at the scripted player's flips in AT (comma list), the DLL last
-- written to DPPH/DPPL walked, and each zone whose list is in the band area
-- (BAND_A-BAND_BEND) listed: its lines, its objects (address, palette and
-- width, x) past the bitmap's two. To shownlists.log. Runs playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local want = {}
for n in (os.getenv("AT") or "202"):gmatch("%d+") do want[tonumber(n)] = true end
local o = io.open("shownlists.log", "w")
local function b(a) return mem:read_u8(a) end
local dpph, dppl = 0, 0
TD = mem:install_write_tap(0x2C, 0x2C, "slh", function(a, d) dpph = d end)
TL = mem:install_write_tap(0x30, 0x30, "sll", function(a, d) dppl = d end)
local done = {}
emu.register_frame_done(function()
  local n = PLAYKEY_N or 0
  if not want[n] or done[n] then return end
  done[n] = true
  local dll = dpph * 256 + dppl
  o:write(string.format("flip %d: DLL $%04X ($07 %02X)\n", n, dll, b(S.S_FBUF)))
  local line = 0
  for e = 0, 84 do
    local b0 = b(dll + 3 * e)
    local a = b(dll + 3 * e + 1) * 256 + b(dll + 3 * e + 2)
    local h = (b0 & 0x0F) + 1
    if a >= S.BAND_A and a < S.BAND_BEND then
      local objs, p = {}, a + 8
      while b(p + 1) ~= 0 do
        objs[#objs + 1] = string.format("$%02X%02X w%d x%d", b(p + 2), b(p), (-(b(p + 1)) & 0x1F), b(p + 3))
        p = p + 4
      end
      o:write(string.format("  line %3d +%d list $%04X: %s\n", line, h, a, table.concat(objs, ", ")))
    end
    line = line + h
    if line >= 243 then break end
  end
  o:flush()
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
