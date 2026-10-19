-- (debug) a companion of p7800-stateplay.lua (SPALSO): DUMPN (comma list of
-- flips, STATEPLAY_N), DUMPF frames after each: the DLL MARIA shows
-- (DPPH/DPPL as written, $2C/$30) and each zone's list, objects decoded, to
-- dldump2.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local want = {}
for t in (os.getenv("DUMPN") or ""):gmatch("%d+") do want[tonumber(t)] = true end
local DF = tonumber(os.getenv("DUMPF") or "2")
local log = io.open("dldump2.log", "w")
local dpp = {[0x2C] = 0, [0x30] = 0}
DLD2_TAP = mem:install_write_tap(0x2C, 0x30, "dld2", function(a, d)
  if a == 0x2C or a == 0x30 then dpp[a] = d end
end)
local last, cnt = -1, 0
local DLLAT = tonumber(os.getenv("DLLAT") or "0", 16)    -- (DLLAT: this DLL, not the one shown)
local function dump(n)
  local dll = DLLAT ~= 0 and DLLAT or dpp[0x2C] * 256 + dpp[0x30]
  log:write(string.format("flip %d: DLL $%04X\n", n, dll))
  local line = 0
  for z = 0, 40 do
    local b0 = mem:read_u8(dll + 3 * z)
    local dl = mem:read_u8(dll + 3 * z + 1) * 256 + mem:read_u8(dll + 3 * z + 2)
    local h = (b0 & 15) + 1
    local s = string.format(" z%02d line %3d h%2d f%02X DL $%04X:", z, line, h, b0, dl)
    local p = dl
    for k = 1, 24 do
      local m = mem:read_u8(p + 1)
      if m == 0 then s = s .. " end"; break end
      if (m & 0x1F) == 0 then       -- (5 bytes: extended)
        s = s .. string.format(" [%02X%02X m%02X pw%02X x%d]", mem:read_u8(p + 2), mem:read_u8(p), m, mem:read_u8(p + 3), mem:read_u8(p + 4))
        p = p + 5
      else
        s = s .. string.format(" (%02X%02X pw%02X x%d)", mem:read_u8(p + 2), mem:read_u8(p), m, mem:read_u8(p + 3))
        p = p + 4
      end
    end
    log:write(s .. "\n")
    line = line + h
    if line >= 243 then break end
  end
  log:flush()
end
emu.register_frame_done(function()
  local n = _G.STATEPLAY_N or -1
  if n ~= last then last, cnt = n, 0 else cnt = cnt + 1 end
  if want[n] and cnt == DF then dump(n) end
end)
