-- (debug) what the ROM is used for, by bank and phase (FINDINGS "The ROM
-- by scene: the plan"): the CPU's opcode fetches (x) and its own data reads
-- (r: the instruction's effective address, decoded as tmp-romable.lua does)
-- in $8000-$FFFF, the window's bank from S_BANK; MARIA's fetches (m, its own
-- "dma" space) in $4000-$FFFF. Context: the bank ("F" the fixed bank at
-- $C000), the phase (L a load under the blank list, T the title's or story's
-- text, P play), the scene (G_ZD0). To romuse.log at each 2000th frame: per
-- context and kind a line "bank phase scene kind page bits" (a hex digit 4
-- bytes, as ramlive.log). Runs playkey.lua (not under port/replay.sh).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local ms = M.devices[":maria"] and M.devices[":maria"].spaces["dma"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local st = cpu.state
local r0 = io.open(os.getenv("PROBES") .. "/tmp-romable.lua"):read("a")
local chunk = r0:sub(r0:find("local function ea%(pc%)"), r0:find("local reg = {%[0x2C%]") - 1)
local env = setmetatable({mem = mem, st = st}, {__index = _G})
local ea, STORE = load(chunk .. "\nreturn ea, STORE", "ea", "t", env)()
local reg = {[0x2C] = 0, [0x30] = 0}
local busy, f = false, 0
local sets = {}
local ph, sc, bank = "L", 0, 0
-- (from the port's boot clear on: the BIOS reads the fixed bank for its
-- signature check at boot)
local c0, c1 = S.ClrRam, S.ClrCart + 16
local booted = false
local function mark(kind, a, bk)
  if not booted then return end
  local k = string.format("%s %s %d %s", bk, ph, sc, kind)
  local s = sets[k]
  if not s then s = {}; sets[k] = s end
  s[a] = true
end
local function upd()
  busy = true
  if reg[0x2C] * 256 + reg[0x30] == S.BLANK_DLL then ph = "L"
  elseif mem:read_u8(S.S_STORY) ~= 0 or mem:read_u8(S.S_TITLEA) ~= 0 or mem:read_u8(S.S_TITLEB) ~= 0 then ph = "T"
  else ph = "P" end
  sc = mem:read_u8(S.G_ZD0)
  bank = mem:read_u8(S.S_BANK)
  busy = false
end
TREG = mem:install_write_tap(0x2C, 0x30, "ru_reg", function(a, d) if reg[a] then reg[a] = d end end)
-- (S_BANK each write: the window's bank as the code keeps it)
TBK = mem:install_write_tap(S.S_BANK, S.S_BANK, "ru_bank", function(a, d) bank = d end)
TR = mem:install_read_tap(0x8000, 0xFFFF, "ru_r", function(a, d)
  if busy then return d end
  local pc = st["PC"].value
  if not booted and pc >= c0 and pc < c1 then booted = true end
  local bk = a >= 0xC000 and "F" or tostring(bank)
  if a == pc then mark("x", a, bk); return d end
  busy = true
  local e1, e2
  if not STORE[mem:read_u8(pc)] then e1, e2 = ea(pc) end
  busy = false
  if e1 == a or e2 == a then mark("r", a, bk) end
  return d
end)
if ms then                -- (the old-timing MAME the replays use has no MARIA space)
  TM = ms:install_read_tap(0x4000, 0xFFFF, "ru_m", function(a, d)
    mark("m", a, a >= 0xC000 and "F" or (a < 0x8000 and "C" or tostring(bank)))
    return d
  end)
end
local function dump()
  local o = io.open("romuse.log", "w")
  for k, s in pairs(sets) do
    local pages = {}
    for a in pairs(s) do
      local p = a >> 8
      local t = pages[p]
      if not t then t = {}; for i = 1, 64 do t[i] = 0 end; pages[p] = t end
      local i = (a & 0xFF) // 4 + 1
      t[i] = t[i] | (8 >> (a & 3))
    end
    for p, t in pairs(pages) do
      local h = {}
      for i = 1, 64 do h[i] = string.format("%X", t[i]) end
      o:write(string.format("%s %02X %s\n", k, p, table.concat(h)))
    end
  end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  upd()
  if f % 2000 == 0 then dump() end
  -- (END: stop there; under PLAYBACK nothing else stops it)
  if os.getenv("END") and f >= tonumber(os.getenv("END")) then dump(); manager.machine:exit() end
end)
-- (and when MAME stops otherwise, -exit_after_playback: the last frames too)
ROMUSE_STOP = emu.add_machine_stop_notifier(function() dump() end)
if not os.getenv("PLAYBACK") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
