-- (debug) the CPU's use of cart RAM ($4000-$7FFF): its writes and its own
-- reads (the instruction's effective address, decoded as tmp-romable.lua
-- does; stores left out), after the boot's clear, per phase (L under the
-- blank list: a load; T with the title's or story's text up; P play), page
-- and PC: counts, to cramuse.log at each 1000th frame ("kind phase page pc
-- count"). FINDINGS "The CPU's data out of cart RAM". Runs playkey.lua (not
-- under port/replay.sh).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local c0, c1 = S.ClrRam, S.ClrCart + 16
local r0 = io.open(os.getenv("PROBES") .. "/tmp-romable.lua"):read("a")
local st = cpu.state
-- (tmp-romable.lua's ea() and STORE, taken as they are)
local chunk = r0:sub(r0:find("local function ea%(pc%)"), r0:find("local reg = {%[0x2C%]") - 1)
local env = setmetatable({mem = mem, st = st}, {__index = _G})
assert(load(chunk .. "\nreturn ea, STORE", "ea", "t", env))
local ea, STORE = load(chunk .. "\nreturn ea, STORE", "ea", "t", env)()
local reg = {[0x2C] = 0, [0x30] = 0}
local booted, busy, f = false, false, 0
local cnt = {}
local function phase()
  if reg[0x2C] * 256 + reg[0x30] == S.BLANK_DLL then return "L" end
  busy = true
  local t = mem:read_u8(S.S_STORY) ~= 0 or mem:read_u8(S.S_TITLEA) ~= 0 or mem:read_u8(S.S_TITLEB) ~= 0
  busy = false
  return t and "T" or "P"
end
local BYADDR = os.getenv("BYADDR")     -- (the address instead of its page)
local function count(kind, a, pc)
  local k = string.format(BYADDR and "%s %s %04X %04X" or "%s %s %02X %04X", kind, phase(), BYADDR and a or a >> 8, pc)
  cnt[k] = (cnt[k] or 0) + 1
end
TREG = mem:install_write_tap(0x2C, 0x30, "cu_reg", function(a, d) if reg[a] then reg[a] = d end end)
TW = mem:install_write_tap(0x4000, 0x7FFF, "cu_w", function(a, d)
  if busy then return end
  local pc = st["PC"].value
  if pc >= c0 and pc < c1 then booted = true; return end
  if booted then count("w", a, st["CURPC"] and st["CURPC"].value or pc) end   -- (CURPC: the writing instruction's own)
end)
TR = mem:install_read_tap(0x4000, 0x7FFF, "cu_r", function(a, d)
  if busy or not booted then return d end
  local pc = st["PC"].value
  if a == pc then return d end
  busy = true
  local e1, e2
  if not STORE[mem:read_u8(pc)] then e1, e2 = ea(pc) end
  busy = false
  if e1 == a or e2 == a then count("r", a, pc) end
  return d
end)
local function dump()
  local o = io.open("cramuse.log", "w")
  local ks = {}
  for k in pairs(cnt) do ks[#ks + 1] = k end
  table.sort(ks)
  for _, k in ipairs(ks) do o:write(k .. " " .. cnt[k] .. "\n") end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if f % 1000 == 0 then dump() end
end)
if not os.getenv("PLAYBACK") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
