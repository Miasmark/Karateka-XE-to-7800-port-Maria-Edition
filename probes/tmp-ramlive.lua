-- (debug) console RAM ($1800-$27FF) live, by scene and phase (FINDINGS
-- "Console RAM laid out scene by scene"): per byte, per context (the scene's
-- bank S_SCENEBANK; the phase: L the load, MARIA showing the blank list; T
-- the title's or story's text up, S_STORY/S_TITLEA/S_TITLEB; P play), the
-- CPU's data reads (as p7800-cpureads.lua decides), its writes and MARIA's
-- reads (its own "dma" space: the patched MAME's, mame_mariaspace.py).
-- After the boot's clear. To ramlive.log at each 2000th frame and END: per
-- context and kind (r, w, m) a line "ctx kind page bits" (a hex digit 4
-- bytes, as ramclass.log). Runs playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local ms = M.devices[":maria"].spaces["dma"]
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
local booted, busy, scene = false, false, 0
local seen = {}
local function ctx()
  local ph = "P"
  if reg[0x2C] * 256 + reg[0x30] == blank then ph = "L"
  else
    busy = true
    if mem:read_u8(S.S_STORY) ~= 0 or mem:read_u8(S.S_TITLEA) ~= 0 or mem:read_u8(S.S_TITLEB) ~= 0 then ph = "T" end
    busy = false
  end
  return string.format("%02X%s", scene, ph)
end
local function mark(kind, a)
  local k = ctx() .. " " .. kind
  local t = seen[k]
  if not t then t = {}; seen[k] = t end
  t[a] = true
end
TREG = mem:install_write_tap(0x2C, 0x30, "rl_reg", function(a, d) if reg[a] then reg[a] = d end end)
TW = mem:install_write_tap(0x1800, 0x27FF, "rl_w", function(a, d)
  if busy then return end
  if a == S.S_SCENEBANK then scene = d end
  local pc = st["PC"].value
  if pc >= c0 and pc < c1 then booted = true; return end
  if booted then mark("w", a) end
end)
TR = mem:install_read_tap(0x1800, 0x27FF, "rl_r", function(a, d)
  if busy or not booted then return d end
  local pc = st["PC"].value
  if a == pc then return d end
  busy = true
  local e1, e2
  if not STORE[mem:read_u8(pc)] then e1, e2 = ea(pc) end
  busy = false
  if e1 == a or e2 == a then mark("r", a) end
  return d
end)
TM = ms:install_read_tap(0x1800, 0x27FF, "rl_m", function(a, d)
  if booted and not busy then mark("m", a) end
  return d
end)
local f = 0
local function dump()
  local o = io.open("ramlive.log", "w")
  for k, t in pairs(seen) do
    for page = 0x18, 0x27 do
      local s, any = {}, false
      for b = 0, 255, 4 do
        local v = 0
        for j = 0, 3 do if t[page * 256 + b + j] then v = v | (8 >> j); any = true end end
        s[#s + 1] = string.format("%X", v)
      end
      if any then o:write(string.format("%s %02X %s\n", k, page, table.concat(s))) end
    end
  end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if f % 2000 == 0 or f == END then dump() end
end)
if not os.getenv("PLAYBACK") then dofile(os.getenv("PROBES") .. "/playkey.lua") end   -- (under port/replay.sh: the recording plays)
