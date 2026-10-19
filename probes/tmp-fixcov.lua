-- (debug) the CPU's own use of the fixed bank ($C000-$FFFF): each byte it
-- fetches as an instruction's (opcode and operands, from the PC) or reads
-- as data (the effective address of the instruction at the PC, as
-- p7800-cpureads.lua decides); MARIA's fetches through the same space (its
-- half's fixed bank: the fighters' parts) left out. From the BIOS's
-- hand-over; a bitmap of 16,384 bytes (1 used) to fixcov.bin at END. Runs
-- playkey.lua unless NOPLAY (as p7800-stateplay.lua's SPALSO: NOPLAY=1).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local END = tonumber(os.getenv("END") or "6000")
local st = cpu.state
local on = false
TFC0 = mem:install_write_tap(0x0001, 0x0001, "fc0", function(a, d)
  if (d & 0x05) == 0x05 then on = true end
end)
local function ea(pc)
  local op = mem:read_u8(pc)
  local lo, hi = mem:read_u8(pc + 1), mem:read_u8(pc + 2)
  local x, y = st["X"].value, st["Y"].value
  local cc, bbb = op & 3, (op >> 2) & 7
  local abs = lo + 256 * hi
  if cc == 1 then
    if bbb == 0 then local p = (lo + x) & 0xFF; return mem:read_u8(p) + 256 * mem:read_u8((p + 1) & 0xFF) end
    if bbb == 3 then return abs end
    if bbb == 4 then return (mem:read_u8(lo) + 256 * mem:read_u8((lo + 1) & 0xFF) + y) & 0xFFFF end
    if bbb == 6 then return (abs + y) & 0xFFFF end
    if bbb == 7 then return (abs + x) & 0xFFFF end
  elseif cc == 2 then
    if bbb == 3 then return abs end
    if bbb == 7 then return (abs + ((op == 0xBE) and y or x)) & 0xFFFF end
  elseif cc == 0 then
    if bbb == 3 and op ~= 0x4C and op ~= 0x6C and op ~= 0x20 then return abs end
    if bbb == 7 and op == 0xBC then return (abs + x) & 0xFFFF end
    if op == 0x6C then return abs end
  end
  return nil
end
local used = {}
TFC1 = mem:install_read_tap(0xC000, 0xFFFF, "fc1", function(a, d)
  if not on then return d end
  local pc = st["PC"].value
  if a >= pc and a <= pc + 2 then
    used[a] = true
    return d
  end
  local e = ea(pc)
  if e and (e == a or e == ((a - 0x100) & 0xFFFF) or (mem:read_u8(pc) == 0x6C and (a == e or a == e + 1))) then
    used[a] = true
  end
  return d
end)
local f, done = 0, false
local function out()
  if done then return end
  done = true
  local t = {}
  for i = 0, 0x3FFF do t[#t + 1] = used[0xC000 + i] and "\1" or "\0" end
  local o = io.open("fixcov.bin", "wb")
  o:write(table.concat(t))
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if f == END then out() end
end)
RU_FCS = emu.add_machine_stop_notifier(out)   -- (a replay ends with its records)
if not os.getenv("NOPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
