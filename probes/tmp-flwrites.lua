-- writes by the floor's code outside its own RAM
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local f, n = 0, 0
local o = io.open("flwrites.log", "w")
local R = {{0x870E, 0x8871}, {0x81DB, 0x82BD}, {0x9552, 0x961F}, {0x9620, 0x96D4}, {0x9D8B, 0x9DF1}}
local function infloor(pc)
  if pc >= 0xE250 and pc < 0xE3A8 then return true end
  if pc >= 0xF4A1 and pc < 0xF4C0 then return true end
  local b = mem:read_u8(S.S_BANK)
  if b > 4 then return false end
  for _, r in ipairs(R) do if pc >= r[1] and pc <= r[2] then return true end end
  return false
end
local function ok(a)
  return a == S.S_BANK or (a >= 0x5800 and a <= 0x60FF) or (a >= 0x0040 and a <= 0x01FF) or (a >= 0x7D5F and a <= 0x7D61)
end
local function tap(lo, hi, nm)
  return mem:install_write_tap(lo, hi, nm, function(a, d)
    if n >= 300 then return end
    local pc = cpu.state["PC"].value
    if infloor(pc) and not ok(a) then
      n = n + 1
      o:write(string.format("f%d flip %s PC %04X wrote $%04X = %02X bank %d\n", f, tostring(PLAYKEY_N), pc, a, d, mem:read_u8(S.S_BANK)))
      o:flush()
    end
  end)
end
TW1 = tap(0x1800, 0x27FF, "w1")
TW2 = tap(0x4000, 0x7FFF, "w2")
emu.register_frame_done(function() f = f + 1 end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
