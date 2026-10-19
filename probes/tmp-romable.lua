-- (debug) could it be ROM? Console RAM ($1800-$27FF) and cart RAM
-- ($4000-$7FFF) byte by byte, after the boot's clear: per byte and scene
-- (S_SCENEBANK), the writes while a load shows the blank list (BLANK_DLL)
-- and in play, the play writes that changed the byte, the values written
-- (up to 6 distinct), and the CPU's data reads (the instruction at the PC
-- has that effective address, as p7800-cpureads.lua decides; JMP (abs)'s
-- pointer too). To romable.log at each 500th frame and END:
--   addr scene loadw playw playchg reads v1,v2,...
-- Runs playkey.lua, so its env applies. MARIA's reads come from
-- p7800-ramclass.lua's runs (probes/romable.py merges them).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local c0, c1 = S.ClrRam, S.ClrCart + 16
local END = tonumber(os.getenv("END") or "6000")
local st = cpu.state
local function ea(pc)
  local op = mem:read_u8(pc)
  local lo, hi = mem:read_u8(pc + 1), mem:read_u8(pc + 2)
  local x, y = st["X"].value, st["Y"].value
  local cc, bbb = op & 3, (op >> 2) & 7
  local abs = lo + 256 * hi
  if op == 0x6C then return abs, abs + 1 end
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
    if bbb == 3 and op ~= 0x4C and op ~= 0x20 then return abs end
    if bbb == 7 and op == 0xBC then return (abs + x) & 0xFFFF end
  end
  return nil
end
local STORE = {}
for _, op in ipairs({0x81, 0x85, 0x8D, 0x91, 0x95, 0x99, 0x9D, 0x84, 0x8C, 0x94, 0x86, 0x8E, 0x96}) do STORE[op] = true end
local reg = {[0x2C] = 0, [0x30] = 0}
local blank = S.BLANK_DLL
local booted, f = false, 0
local rec = {}            -- [scene][addr] = {loadw, playw, playchg, reads, vals{}, nv}
local scene, busy = 0, false   -- (busy: the taps' own reads inside the ranges)
local function slot(a)
  local sc = scene
  local t = rec[sc]
  if not t then t = {}; rec[sc] = t end
  local r = t[a]
  if not r then r = {0, 0, 0, 0, {}, 0}; t[a] = r end
  return r
end
TREG = mem:install_write_tap(0x2C, 0x30, "rb_reg", function(a, d) if reg[a] then reg[a] = d end end)
local function onwrite(a, d)
  if busy then return end
  if a == S.S_SCENEBANK then scene = d end
  local pc = st["PC"].value
  if pc >= c0 and pc < c1 then booted = true; return end
  if not booted then return end
  local r = slot(a)
  if reg[0x2C] * 256 + reg[0x30] == blank then r[1] = r[1] + 1
  else
    r[2] = r[2] + 1
    busy = true
    local old = mem:read_u8(a)
    busy = false
    if old ~= d then r[3] = r[3] + 1 end
  end
  if not r[5][d] and r[6] < 6 then r[5][d] = true; r[6] = r[6] + 1 end
end
local function onread(a, d)
  if busy or not booted then return d end
  local pc = st["PC"].value
  if a == pc then return d end
  busy = true
  local e1, e2
  if not STORE[mem:read_u8(pc)] then e1, e2 = ea(pc) end
  busy = false
  if e1 == a or e2 == a then local r = slot(a); r[4] = r[4] + 1 end
  return d
end
TW1 = mem:install_write_tap(0x1800, 0x27FF, "rb_w1", onwrite)
TW2 = mem:install_write_tap(0x4000, 0x7FFF, "rb_w2", onwrite)
TR1 = mem:install_read_tap(0x1800, 0x27FF, "rb_r1", onread)
TR2 = mem:install_read_tap(0x4000, 0x7FFF, "rb_r2", onread)
local function dump()
  local o = io.open("romable.log", "w")
  for sc, t in pairs(rec) do
    for a, r in pairs(t) do
      local v = {}
      for k in pairs(r[5]) do v[#v + 1] = string.format("%02X", k) end
      table.sort(v)
      o:write(string.format("%04X %02X %d %d %d %d %s\n", a, sc, r[1], r[2], r[3], r[4], table.concat(v, ",")))
    end
  end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if f % 500 == 0 or f == END then dump() end
end)
if not os.getenv("PLAYBACK") then dofile(os.getenv("PROBES") .. "/playkey.lua") end   -- (under port/replay.sh: the recording plays)
