-- (debug) playkey.lua, plus: every CPU read of cart RAM ($4000-$7FFF), by page
-- and by the reading PC (counts), to cartread.log at END - 5 frames. The
-- user's rule: the CPU writes cart RAM (MARIA's pseudo-ROM), never reads it;
-- display lists go to console RAM. MARIA's DMA reads go through the same
-- space (the tap sees them too), so a read counts only when it is the
-- effective address of the instruction at PC (its addressing mode decoded);
-- the rest are MARIA's (or a read-modify-write's second access).
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local bypage, bypc, bypp, f = {}, {}, {}, 0
local maria, stores = 0, 0
local END = tonumber(os.getenv("END") or "300")
-- the 6502's addressing modes by opcode (low 5 bits pattern): returns the
-- effective address of the instruction at pc, or nil
local function rd(a) return mem:read_u8(a) end
local function ea(pc)
  local op = rd(pc)
  local lo, hi = rd(pc + 1), rd(pc + 2)
  local x, y = cpu.state["X"].value & 0xFF, cpu.state["Y"].value & 0xFF
  local cc, bbb = op & 3, (op >> 2) & 7
  if cc == 1 then
    if bbb == 0 then local p = (lo + x) & 0xFF; return rd(p) + 256 * rd((p + 1) & 0xFF) end
    if bbb == 1 then return lo end
    if bbb == 3 then return lo + 256 * hi end
    if bbb == 4 then return (rd(lo) + 256 * rd((lo + 1) & 0xFF) + y) & 0xFFFF end
    if bbb == 5 then return (lo + x) & 0xFF end
    if bbb == 6 then return (lo + 256 * hi + y) & 0xFFFF end
    if bbb == 7 then return (lo + 256 * hi + x) & 0xFFFF end
  elseif cc == 2 or cc == 0 then
    if bbb == 1 then return lo end
    if bbb == 3 then return lo + 256 * hi end
    if bbb == 5 then return (lo + ((op == 0xB6 or op == 0x96) and y or x)) & 0xFF end
    if bbb == 7 then return (lo + 256 * hi + ((op == 0xBE) and y or x)) & 0xFFFF end
  end
  return nil
end
local busy = false
local S1 = SYM_ADDR and SYM_ADDR.S_L1
local ONLYL1 = os.getenv("ONLYL1")         -- (ONLYL1=1: only while S_L1 is on)
TCR = mem:install_read_tap(0x4000, 0x7FFF, "cartr", function(a, d)
  if busy then return d end
  if ONLYL1 and S1 and mem:read_u8(S1) ~= 1 then return d end
  busy = true
  local pc = cpu.state["PC"].value
  local e = (pc < 0x4000 or pc >= 0x8000) and ea(pc) or nil
  busy = false
  if e ~= a then maria = maria + 1; return d end
  local op = mem:read_u8(pc)            -- (an indexed store's dummy read: not a read)
  if op == 0x81 or op == 0x91 or op == 0x99 or op == 0x9D or op == 0x96 or op == 0x94 or op == 0x95 then
    stores = stores + 1
    return d
  end
  local pg = a >> 8
  bypage[pg] = (bypage[pg] or 0) + 1
  local k = string.format("%04X", pc)
  bypc[k] = (bypc[k] or 0) + 1
  local kp = string.format("%04X %02X", pc, pg)
  bypp[kp] = (bypp[kp] or 0) + 1
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f ~= END - 5 then return end
  local o = io.open("cartread.log", "w")
  o:write(string.format("not the CPU's (MARIA's): %d\n", maria))
  local t = {}
  for p, n in pairs(bypage) do t[#t + 1] = {p, n} end
  table.sort(t, function(a, b) return a[1] < b[1] end)
  for _, e in ipairs(t) do o:write(string.format("page %02X %d\n", e[1], e[2])) end
  t = {}
  for k, n in pairs(bypc) do t[#t + 1] = {k, n} end
  table.sort(t, function(a, b) return a[2] > b[2] end)
  for _, e in ipairs(t) do o:write(string.format("pc %s %d %s\n", e[1], e[2], SYM_NAME and SYM_NAME[tonumber(e[1], 16)] or "")) end
  for k, n in pairs(bypp) do o:write(string.format("pp %s %d\n", k, n)) end
  o:close()
end)
