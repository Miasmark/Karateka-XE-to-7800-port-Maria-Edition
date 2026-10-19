-- the CPU's reads of cart RAM (FINDINGS "BankSet: what reads MARIA's RAM"):
-- a read of $4000-$7FFF is the CPU's when the instruction at the PC has
-- that effective address (abs, abs,X, abs,Y, (zp),Y, (zp,X); MARIA's DMA
-- reads come through the same space with an unrelated PC); instruction
-- fetches there are code; stores (whose indexed forms make a dummy read of
-- their target) are left out. Per page and per reading PC (with the bank in
-- for $8000-$BFFF), to cpureads.log at END. Runs playkey.lua unless NOPLAY.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local st = cpu.state
-- addressing modes by opcode (the 6502's regular pattern, plus the 65C02-free NMOS set used here)
local function ea(pc)
  local op = mem:read_u8(pc)
  local lo, hi = mem:read_u8(pc + 1), mem:read_u8(pc + 2)
  local x, y = st["X"].value, st["Y"].value
  local cc, bbb = op & 3, (op >> 2) & 7
  local abs = lo + 256 * hi
  if cc == 1 then           -- ALU group: LDA/STA/ORA/AND/EOR/ADC/CMP/SBC
    if bbb == 0 then local p = (lo + x) & 0xFF; return mem:read_u8(p) + 256 * mem:read_u8((p + 1) & 0xFF) end
    if bbb == 3 then return abs end
    if bbb == 4 then return (mem:read_u8(lo) + 256 * mem:read_u8((lo + 1) & 0xFF) + y) & 0xFFFF end
    if bbb == 6 then return (abs + y) & 0xFFFF end
    if bbb == 7 then return (abs + x) & 0xFFFF end
  elseif cc == 2 then       -- RMW / LDX/STX
    if bbb == 3 then return abs end
    if bbb == 7 then return (abs + ((op == 0xBE) and y or x)) & 0xFFFF end
  elseif cc == 0 then       -- BIT, LDY/STY, CPX/CPY, JMP
    if bbb == 3 and op ~= 0x4C and op ~= 0x6C then return abs end
    if bbb == 7 and op == 0xBC then return (abs + x) & 0xFFFF end
  end
  return nil
end
local STORE = {}
for _, op in ipairs({0x81, 0x85, 0x8D, 0x91, 0x95, 0x99, 0x9D, 0x84, 0x8C, 0x94, 0x86, 0x8E, 0x96}) do STORE[op] = true end
local reads = {}          -- "page pcbank:pc" -> count
local code = {}
local f = 0
TR = mem:install_read_tap(0x4000, 0x7FFF, "cr", function(a, d)
  local pc = st["PC"].value
  if a == pc or (a > pc and a <= pc + 2 and pc >= 0x4000 and pc < 0x8000) then
    code[a >> 8] = (code[a >> 8] or 0) + 1
    return d
  end
  local op = mem:read_u8(pc)
  if STORE[op] then return d end          -- (an indexed store's dummy read of its target)
  local e = ea(pc)
  if e and (e == a or e == ((a - 0x100) & 0xFFFF)) then   -- (an indexed read crossing a page reads the page below first)
    local where = pc >= 0xC000 and "F" or (pc >= 0x8000 and ("b" .. mem:read_u8(S.S_BANK)) or "R")
    local k = string.format("%02X %s:%04X %02X", a >> 8, where, pc, mem:read_u8(pc))
    reads[k] = (reads[k] or 0) + 1
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f == END then
    local o = io.open("cpureads.log", "w")
    for p, n in pairs(code) do o:write(string.format("code %02X %d\n", p, n)) end
    for k, n in pairs(reads) do o:write(string.format("read %s %d\n", k, n)) end
    o:close()
  end
end)
if not os.getenv("NOPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
