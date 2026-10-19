-- Console RAM use per scene (playkey.lua runs alongside): for every byte of
-- the zero page ($40-$FF), the stack page's upper half ($140-$1FF) and the
-- 4K at $1800-$27FF, which scenes ($D0, through ZPMAP) read it and which
-- write it, and whether a scene's first touch is a read (the byte carries
-- something in). At END - 5 frames (or when the run stops), ramuse.txt: one line per byte that any
-- scene touched, "addr R:scenes W:scenes F:scenes-whose-first-touch-is-a-read";
-- untouched bytes are left out. Instruction fetches (code run from RAM)
-- count as reads. Reads by MARIA (its DMA goes through the same space) are
-- told apart as tmp-cartread.lua does: a read counts only when it is the
-- effective address of the instruction at PC, or PC itself (code).
-- NOPLAYKEY=1: as p7800-stateplay.lua's SPALSO companion (no playkey.lua; the
-- zero page map read here)
if not os.getenv("NOPLAYKEY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
if not ZMAP then
  ZMAP = {}
  for z = 0, 255 do ZMAP[z] = z end
  for line in io.lines(os.getenv("ZPMAP")) do
    local z, t = line:match("^(%x+) (%x+)")
    if z then ZMAP[tonumber(z, 16)] = tonumber(t, 16) end
  end
end
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local END = tonumber(os.getenv("RUEND") or os.getenv("END") or "300")
local D0 = ZMAP and ZMAP[0xD0] or 0xD0
local R, W, F = {}, {}, {}
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
local RUSTART = tonumber(os.getenv("RUSTART") or "0")   -- (RUSTART=n: nothing before frame n, as the boot's clear)
local ruf = 0
RU_RUF = emu.add_machine_frame_notifier(function() ruf = ruf + 1 end)
local function mark(t, a, s)
  if ruf < RUSTART then return end
  local e = t[a]
  if not e then e = {}; t[a] = e end
  e[s] = true
end
local function onread(a, d)
  if busy then return d end
  busy = true
  _G.PROBE_PEEK = true                         -- (our own reads: other probes' taps ignore them)
  local pc = cpu.state["PC"].value
  local ok = false
  if a >= pc and a <= pc + 2 then
    ok = true                                  -- (the instruction itself, or its operand)
  else
    local e = ea(pc)
    ok = (e == a) or (e ~= nil and e + 1 == a)   -- (a pointer's second byte)
    if not ok then                             -- (the stack: PLA/PLP/RTS/RTI)
      local sp = 0x100 + (cpu.state["SP"].value & 0xFF)
      ok = a > sp and a <= sp + 3 and a < 0x200
    end
  end
  if ok then
    local s = rd(D0)
    if not (W[a] and W[a][s]) and not (R[a] and R[a][s]) then mark(F, a, s) end
    mark(R, a, s)
  end
  busy = false
  _G.PROBE_PEEK = false
  return d
end
local function onwrite(a, d)
  if busy then return end
  local s = rd(D0)
  mark(W, a, s)
end
TRU1 = mem:install_read_tap(0x0040, 0x00FF, "ru1", onread)
TRU2 = mem:install_read_tap(0x0140, 0x01FF, "ru2", onread)
TRU3 = mem:install_read_tap(0x1800, 0x27FF, "ru3", onread)
TWU1 = mem:install_write_tap(0x0040, 0x00FF, "wu1", onwrite)
TWU2 = mem:install_write_tap(0x0140, 0x01FF, "wu2", onwrite)
TWU3 = mem:install_write_tap(0x1800, 0x27FF, "wu3", onwrite)
local f = 0
local function keys(t)
  local k = {}
  for s in pairs(t or {}) do k[#k + 1] = s end
  table.sort(k)
  local out = {}
  for _, s in ipairs(k) do out[#out + 1] = string.format("%d", s) end
  return table.concat(out, ",")
end
local written = false
local function dump()
  if written then return end
  written = true
  local o = io.open("ramuse.txt", "w")
  o:write(string.format("; frames %d\n", f))
  for a = 0x0040, 0x27FF do
    if R[a] or W[a] then
      o:write(string.format("%04X R:%s W:%s F:%s\n", a, keys(R[a]), keys(W[a]), keys(F[a])))
    end
  end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if f == END - 5 then dump() end
end)
RU_STOP = emu.add_machine_stop_notifier(dump) -- (a companion: the replay may end first;
                                              -- the subscription lasts only while it is kept)
