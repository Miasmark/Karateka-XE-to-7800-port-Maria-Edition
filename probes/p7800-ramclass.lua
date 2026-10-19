-- console RAM ($1800-$27FF) by who needs it (FINDINGS "Console RAM: what
-- must stay"): each frame, the display list list last set (DPPH/DPPL) is
-- walked as MARIA reads it, marking in console RAM the DLL's entries ("L"),
-- the zones' display lists ("D") and the graphics they fetch ("G": direct
-- objects' bytes, indirect objects' maps and characters at CHBASE); every
-- instruction fetched there is "X" (code); every write after the boot's
-- clear "W". To ramclass.log at END (a bit an address, 256 a line, per
-- class). Runs playkey.lua (WITHPLAY is implied), so its env applies.
-- LO, HI (hex): another range (cart RAM: 4000, 7FFF); there the CPU's data
-- reads are "R" too (the instruction at the PC has that effective address,
-- as p7800-cpureads.lua decides; MARIA's DMA reads come through the same
-- space with an unrelated PC; indexed stores' dummy reads left out).
-- NOREAD=1: no read tap (no "X" or "R"; a tap on cart RAM is slow: MARIA's
-- DMA reads fire it).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local c0, c1 = SYM_ADDR.ClrRam, SYM_ADDR.ClrCart + 16
local END = tonumber(os.getenv("END") or "6000")
local LO, HI = tonumber(os.getenv("LO") or "1800", 16), tonumber(os.getenv("HI") or "27FF", 16)
local cls = {L = {}, D = {}, G = {}, X = {}, W = {}, R = {}}
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
    if bbb == 3 and op ~= 0x4C and op ~= 0x6C then return abs end
    if bbb == 7 and op == 0xBC then return (abs + x) & 0xFFFF end
  end
  return nil
end
local STORE = {}
for _, op in ipairs({0x81, 0x85, 0x8D, 0x91, 0x95, 0x99, 0x9D, 0x84, 0x8C, 0x94, 0x86, 0x8E, 0x96}) do STORE[op] = true end
local reg = {[0x2C] = 0, [0x30] = 0, [0x34] = 0}
local booted, f = false, 0
TREG = mem:install_write_tap(0x2C, 0x34, "rc_reg", function(a, d) if reg[a] then reg[a] = d end end)
TW = mem:install_write_tap(LO, HI, "rc_w", function(a, d)
  local pc = cpu.state["PC"].value
  if pc >= c0 and pc < c1 then booted = true; return end
  if booted then cls.W[a] = true end
end)
TX = (not os.getenv("NOREAD")) and mem:install_read_tap(LO, HI, "rc_x", function(a, d)
  if not booted then return d end
  local pc = st["PC"].value
  if a == pc then cls.X[a] = true; return d end
  if LO >= 0x4000 and not STORE[mem:read_u8(pc)] then
    local e = ea(pc)
    if e and e == a then cls.R[a] = true end
  end
  return d
end)
local function rd(a) return mem:read_u8(a & 0xFFFF) end
local function mark(k, a) if a >= LO and a <= HI then cls[k][a] = true end end
local function walk()
  local dll = reg[0x2C] * 256 + reg[0x30]
  local cb = reg[0x34]
  local line = 0
  for e = 0, 100 do
    local p = dll + 3 * e
    mark("L", p); mark("L", p + 1); mark("L", p + 2)
    local fl, hi, lo = rd(p), rd(p + 1), rd(p + 2)
    local off = fl & 0x0F
    local dl = hi * 256 + lo
    for i = 0, off do
      local ov = off - i
      local q = dl
      for n = 1, 64 do
        local b0, b1 = rd(q), rd(q + 1)
        mark("D", q); mark("D", q + 1)
        if b1 == 0 then break end
        local ind, alo, ahi, w
        if (b1 & 0x1F) == 0 then
          for k = 2, 4 do mark("D", q + k) end
          ind = (b1 & 0x20) ~= 0
          alo, ahi = b0, rd(q + 2); w = 32 - (rd(q + 3) & 0x1F)
          q = q + 5
        else
          for k = 2, 3 do mark("D", q + k) end
          ind = false
          alo, ahi = b0, rd(q + 2); w = 32 - (b1 & 0x1F)
          q = q + 4
        end
        for k = 0, w - 1 do
          if ind then
            local m = (ahi * 256 + alo + k) & 0xFFFF
            mark("G", m)
            local code = rd(m)
            mark("G", ((cb + ov) & 0xFF) * 256 + code); mark("G", ((cb + ov) & 0xFF) * 256 + code + 1)
          else
            mark("G", (((ahi + ov) & 0xFF) * 256 + alo + k) & 0xFFFF)
          end
        end
      end
      line = line + 1
    end
    if line >= 243 then break end
  end
end
local function dump()
  local o = io.open("ramclass.log", "w")
  for _, k in ipairs({"L", "D", "G", "X", "W", "R"}) do
    for page = LO >> 8, HI >> 8 do
      local s = {}
      for b = 0, 255, 4 do
        local v = 0
        for j = 0, 3 do if cls[k][page * 256 + b + j] then v = v | (8 >> j) end end
        s[#s + 1] = string.format("%X", v)
      end
      o:write(string.format("%s %02X %s\n", k, page, table.concat(s)))
    end
  end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if booted then walk() end
  if f % 500 == 0 or f == END then dump() end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
