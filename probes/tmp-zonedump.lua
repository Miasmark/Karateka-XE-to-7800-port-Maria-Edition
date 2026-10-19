-- (debug) playkey.lua, plus: at the end of the first frame after flip DUMPK's
-- display list is shown (DPPH/DPPL written with another list), each zone of
-- the shown DLL (its first line, lines, list) and its objects, to
-- zonedump.log; then exit
-- NOPLAYKEY=1: as p7800-stateplay.lua's companion (SPALSO): its flip count
if not os.getenv("NOPLAYKEY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local DUMPK = tonumber(os.getenv("DUMPK") or "240")
SHADOW = {}
if os.getenv("ZDRAM") then              -- (cart RAM reads back $FF here: its writes kept)
  TZR = mem:install_write_tap(0x4000, 0x7FFF, "zdram", function(a, d) SHADOW[a] = d end)
  TZC = mem:install_write_tap(0x34, 0x34, "zdchb", function(a, d) LASTCHB = d end)
end
local dpp = {[0x2C] = 0, [0x30] = 0}
local wait, at, due = false, nil, false
TZD = mem:install_write_tap(0x2C, 0x30, "zdpp", function(a, d)
  if a ~= 0x2C and a ~= 0x30 then return end
  dpp[a] = d
  if wait and dpp[0x2C] * 256 + dpp[0x30] ~= at then wait = false; due = true end
end)
local armed = false
emu.register_frame_done(function()
  local N = os.getenv("NOPLAYKEY") and _G.STATEPLAY_N or PLAYKEY_N
  if not armed and N and N >= DUMPK then
    armed = true; wait = true; at = dpp[0x2C] * 256 + dpp[0x30]
  end
  if not due then return end
  due = false
  local o = io.open("zonedump.log", "w")
  local dll = dpp[0x2C] * 256 + dpp[0x30]
  o:write(string.format("flip %d DLL %04X\n", os.getenv("NOPLAYKEY") and _G.STATEPLAY_N or PLAYKEY_N, dll))
  local line = 0
  for e = 0, 90 do
    local b0, hi, lo = mem:read_u8(dll + 3 * e), mem:read_u8(dll + 3 * e + 1), mem:read_u8(dll + 3 * e + 2)
    local h = (b0 & 15) + 1
    local dl = hi * 256 + lo
    o:write(string.format("zone %d lines %d-%d (%d) b0 %02X list %04X:", e, line, line + h - 1, h, b0, dl))
    local p = dl
    for k = 1, 40 do
      local c0, c1 = mem:read_u8(p), mem:read_u8(p + 1)
      if c1 & 0x1F == 0 then
        if c1 == 0 then break end
        o:write(string.format(" [5:%02X %02X %02X %02X %02X]", c0, c1, mem:read_u8(p + 2), mem:read_u8(p + 3), mem:read_u8(p + 4)))
        p = p + 5
      else
        o:write(string.format(" [%02X %02X %02X x%d]", c0, c1, mem:read_u8(p + 2), mem:read_u8(p + 3)))
        p = p + 4
      end
    end
    o:write("\n")
    line = line + h
    if line >= 260 then break end
  end
  o:close()
  if os.getenv("ZDRAM") then           -- (and $4000-$7FFF as written: zdram.bin; CHBASE's last)
    local r = io.open("zdram.bin", "wb")
    for a = 0x4000, 0x7FFF do r:write(string.char(SHADOW[a] or 0)) end
    r:close()
    r = io.open("zdchb.log", "w"); r:write(string.format("CHBASE %02X", LASTCHB or 0)); r:close()
  end
  M:exit()
end)
