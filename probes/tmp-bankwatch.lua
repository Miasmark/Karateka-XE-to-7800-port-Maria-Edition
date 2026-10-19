-- (debug) playkey.lua, plus: every write to BANKSEL ($8000) while S_L1 is on
-- that selects bank 0 or 4 (their MARIA copies hold the title's data: level
-- 1's top zones misdraw while either is in), with its PC, the caller (the
-- stack's return address), to bankwatch.log (no scanline: this MAME's
-- screen has no vpos, and an error in a tap is silent); each PC once
-- per flip, until END
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = SYM_ADDR
local scr = M.screens[":screen"]
local o = io.open("bankwatch.log", "w")
local seen, lastn = {}, -1
local count = {}
TBW = mem:install_write_tap(0x8000, 0x8000, "bankw", function(a, d)
  if mem:read_u8(S.S_L1) ~= 1 then return end
  if d ~= 0 and d ~= 4 then return end
  local pc = cpu.state["PC"].value
  local sp = cpu.state["SP"].value & 0xFF
  local ret = mem:read_u8(0x101 + sp) + 256 * mem:read_u8(0x102 + sp) + 1
  local key = string.format("%04X<%04X b%d", pc, ret, d)
  count[key] = (count[key] or 0) + 1
  if PLAYKEY_N ~= lastn then seen = {}; lastn = PLAYKEY_N end
  if not seen[key] then
    seen[key] = true
    o:write(string.format("flip %s pc %04X (%s) ret %04X (%s) bank %d\n", tostring(PLAYKEY_N), pc,
      SYM_NAME[pc] or "?", ret, SYM_NAME[ret] or "?", d))
    o:flush()
  end
end)
emu.register_stop(function()
  for k, v in pairs(count) do o:write("total " .. k .. " " .. v .. "\n") end
  o:close()
end)
