-- (debug) the CPU's data reads of ROM ($8000-$FFFF): each byte read (the
-- window's bank, S_BANK, for $8000-$BFFF; F the fixed bank) with the PCs
-- that read it (and the PC's bank), counted, to romreads.log at END. A read
-- is the CPU's when the instruction at the PC has that effective address
-- (as p7800-cpureads.lua decides); opcode and operand fetches are left out.
-- Runs playkey.lua unless NOPLAY.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local st = cpu.state
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
  end
  return nil
end
local reads = {}
local f = 0
TRR = mem:install_read_tap(0x8000, 0xFFFF, "rr", function(a, d)
  local pc = st["PC"].value
  if a >= pc and a <= pc + 2 then return d end
  local e = ea(pc)
  if e and (e == a or e == ((a - 0x100) & 0xFFFF)) then
    local bk = mem:read_u8(S.S_BANK)
    local ab = a >= 0xC000 and "F" or tostring(bk)
    local pb = pc >= 0xC000 and "F" or (pc >= 0x8000 and tostring(bk) or "R")
    local k = string.format("%s:%04X %s:%04X", ab, a, pb, pc)
    reads[k] = (reads[k] or 0) + 1
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f == END then
    local o = io.open("romreads.log", "w")
    for k, n in pairs(reads) do o:write(k .. " " .. n .. "\n") end
    o:close()
  end
end)
if not os.getenv("NOPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
