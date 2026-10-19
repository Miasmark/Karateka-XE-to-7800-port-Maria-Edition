-- (debug) could buffer B's table share buffer A's bytes? For each pair (A's
-- range, B's, the same length), per offset i, which half wrote last; a CPU
-- read of A[i] when B[i] was written after A[i] (or the reverse) would read
-- the other buffer's value if B lay over A: a conflict. Per pair: reads,
-- conflicts, the frames they were in (the first 8) and their PCs. To
-- abshare.log at each 1000th frame. Runs playkey.lua (not under
-- port/replay.sh); the no-rules MAME (taps on cart RAM).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
-- name, A's start, B's start, length
local PAIRS = {
  {"FO_CELL", S.FO_CELL, S.FO_CELL + 40, 40}, {"FO_X", S.FO_X, S.FO_X + 40, 40},
  {"FO_PW", S.FO_PW, S.FO_PW + 40, 40}, {"FO_LO", S.FO_LO, S.FO_LO + 40, 40},
  {"FO_HB", S.FO_HB, S.FO_HB + 40, 40},
  {"SORT", S.FS_I, S.FS_I + S.FS_BOFF, 80},
  {"ZT_DLL", S.ZT_DLL, S.ZT_DLL + 16, 16}, {"ZT_CELL", S.ZT_CELL, S.ZT_CELL + 16, 16},
  {"ZT_H", S.ZT_H, S.ZT_H + 16, 16},
  {"L1_SH", S.L1_SHA, S.L1_SHB, 24}, {"L1_X", S.L1_XA, S.L1_XB, 24},
  {"TOPLI", S.TOPLI, S.TOPLI + 28, 28}, {"TOPLX", S.TOPLX, S.TOPLX + 28, 28},
  {"TOPLK0", S.TOPLK0, S.TOPLK0 + 28, 28}, {"TOPLK1", S.TOPLK1, S.TOPLK1 + 28, 28},
  {"TOPZ_ARG", S.TOPZ_ARG, S.TOPZ_ARG + 10, 10}, {"TOPZ_H", S.TOPZ_H, S.TOPZ_H + 10, 10},
  {"TP_DLL", S.TP_DLL, S.TP_DLL + 20, 20},
  {"STATUS", S.STATUS_DLA, S.STATUS_DLB, 76},
}
-- (a read counts only when it is the instruction's own: its effective
-- address decoded as tmp-romable.lua does, stores left out, whose indexed
-- forms read their target first; and after the boot's clear)
local c0, c1 = S.ClrRam, S.ClrCart + 16
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
local booted, busy = false, false
local f = 0
local st = {}
for k, p in ipairs(PAIRS) do st[k] = {last = {}, reads = 0, conf = 0, frames = {}, pcs = {}} end
TAPS = {}                               -- (global: a collected tap is removed)
for k, p in ipairs(PAIRS) do
  local name, a0, b0, n = p[1], p[2], p[3], p[4]
  local s = st[k]
  local function half(a)
    if a >= a0 and a < a0 + n then return "A", a - a0 end
    if a >= b0 and a < b0 + n then return "B", a - b0 end
  end
  local lo, hi = math.min(a0, b0), math.max(a0, b0) + n - 1
  TAPS[#TAPS + 1] = mem:install_write_tap(lo, hi, "abw" .. k, function(a, d)
    local h, i = half(a)
    local pc = cpu.state["PC"].value
    if pc >= c0 and pc < c1 then booted = true end
    if h then s.last[i] = h end
  end)
  TAPS[#TAPS + 1] = mem:install_read_tap(lo, hi, "abr" .. k, function(a, d)
    local h, i = half(a)
    local pc = cpu.state["PC"].value
    if not h or busy or not booted or a == pc then return d end
    busy = true
    local e1, e2
    if not STORE[mem:read_u8(pc)] then e1, e2 = ea(pc) end
    busy = false
    if e1 ~= a and e2 ~= a then return d end
    s.reads = s.reads + 1
    if s.last[i] and s.last[i] ~= h then
      s.conf = s.conf + 1
      s.frames[f] = true
      s.pcs[pc] = (s.pcs[pc] or 0) + 1
    end
    return d
  end)
end
emu.register_frame_done(function()
  f = f + 1
  if f % 1000 == 0 then
    local o = io.open("abshare.log", "w")
    for k, p in ipairs(PAIRS) do
      local s = st[k]
      local fr, nf, pcs = {}, 0, {}
      for k2 in pairs(s.frames) do nf = nf + 1; fr[#fr + 1] = k2 end
      table.sort(fr)
      for k2, v in pairs(s.pcs) do pcs[#pcs + 1] = string.format("$%04X:%d", k2, v) end
      table.sort(pcs)
      o:write(string.format("%-9s %3d bytes a half: reads %d, conflicts %d in %d frames (first %s) at %s\n", p[1], p[4],
        s.reads, s.conf, nf, table.concat(fr, ",", 1, math.min(#fr, 8)), table.concat(pcs, " ")))
    end
    o:close()
  end
end)
if not os.getenv("PLAYBACK") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
