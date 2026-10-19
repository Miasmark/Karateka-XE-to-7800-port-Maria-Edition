-- (debug) playkey.lua, plus: at frame AT, the shown DLL (DPPH/DPPL as
-- written) entry by entry: its first line, height, DLI flag, list address;
-- and from frame AT1 to AT, every palette the shown lists' headers use
-- (lines 48-239, while S_L1 is on), with the zones' first lines; to
-- dlldump.log
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local S = SYM_ADDR
local AT = tonumber(os.getenv("AT") or "1500")
local AT1 = tonumber(os.getenv("AT1") or tostring(AT))
local dpp = {[0x2C] = 0, [0x30] = 0}
TDD = mem:install_write_tap(0x2C, 0x30, "dddpp", function(a, d)
  if a == 0x2C or a == 0x30 then dpp[a] = d end
end)
local f = 0
local pals = {}
for p = 0, 7 do pals[p] = {} end
local function walk(a, line)
  local n = 0
  for k = 1, 40 do
    local c1 = mem:read_u8(a + n + 1)
    local p
    if c1 & 0x1F == 0 then
      if c1 == 0 then return end
      p = mem:read_u8(a + n + 3) >> 5
      n = n + 5
    else
      p = c1 >> 5
      n = n + 4
    end
    pals[p][line] = (pals[p][line] or 0) + 1
  end
end
RU_DP = emu.add_machine_frame_notifier(function()
  if f < AT1 or f > AT or (S.S_L1 and mem:read_u8(S.S_L1) ~= 1) then return end
  local dll = dpp[0x2C] * 256 + dpp[0x30]
  local line = 0
  for e = 0, 90 do
    local b0, hi, lo = mem:read_u8(dll + 3 * e), mem:read_u8(dll + 3 * e + 1), mem:read_u8(dll + 3 * e + 2)
    if line >= 48 and line < 240 then walk(hi * 256 + lo, line) end
    line = line + (b0 & 15) + 1
    if line > 262 then break end
  end
end)
RU_DD = emu.add_machine_frame_notifier(function()
  f = f + 1
  if f ~= AT then return end
  local o = io.open("dlldump.log", "w")
  local dll = dpp[0x2C] * 256 + dpp[0x30]
  o:write(string.format("DLL $%04X\n", dll))
  local line = 0
  for e = 0, 90 do
    local b0, hi, lo = mem:read_u8(dll + 3 * e), mem:read_u8(dll + 3 * e + 1), mem:read_u8(dll + 3 * e + 2)
    local h = (b0 & 15) + 1
    o:write(string.format("line %3d h %2d %s list $%02X%02X ctrl %02X\n", line, h, b0 & 0x80 ~= 0 and "DLI" or "   ", hi, lo, b0))
    line = line + h
    if line > 262 then break end
  end
  for p = 0, 7 do
    local t = {}
    for l, n in pairs(pals[p]) do t[#t + 1] = l end
    table.sort(t)
    local u = {}
    for _, l in ipairs(t) do u[#u + 1] = string.format("%d(%d)", l, pals[p][l]) end
    o:write("palette " .. p .. ": " .. table.concat(u, " ") .. "\n")
  end
  o:close()
end)
