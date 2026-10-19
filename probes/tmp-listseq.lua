-- (debug) the lists' demand, for probes/listsim.py: every rebuild of a row's
-- pieces (band: BandL1Start, L1_SG the row; top: TopSegStart, TP_SG at its
-- first TpPlace) and the lists then placed in it, in order. Band: at
-- BandWL1 the estimate S_FL0 (what a piece must have room for), at BandWEnd
-- the real size (Y + 2: what the pointer then moves); "e:x" when no piece
-- had room (BandWL1X: objects dropped, then another try). Top: at TpPlace
-- S_EW + 2 (exact: TopEmit counts first), counted at TpPlF. Each rebuild one line, "kind row
-- phase sizes" (phase L under the blank list, T with the title's or story's
-- text up, P play; then the scene, the game's $D0), identical lines counted: to listseq.log at each 2000th
-- frame and END. Runs playkey.lua. Needs the no-rules MAME (it reads cart
-- RAM inside taps).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local function r(a) return mem:read_u8(a) end
local reg = {[0x2C] = 0, [0x30] = 0}
local count = {}
local band, top = nil, nil         -- {row, phase, sizes}
local pend = nil
local function phase()
  if reg[0x2C] * 256 + reg[0x30] == S.BLANK_DLL then return "L" end
  if r(S.S_STORY) ~= 0 or r(S.S_TITLEA) ~= 0 or r(S.S_TITLEB) ~= 0 then return "T" end
  return "P"
end
local function flush(e, kind)
  if e and #e.sizes > 0 then
    local k = string.format("%s %02X %s%d %s", kind, e.row, e.phase, e.scene, table.concat(e.sizes, " "))
    count[k] = (count[k] or 0) + 1
  end
end
-- (the routines are in banked ROM: another bank's code at the same address
-- fires the tap too, so each checks its own operand bytes after the opcode)
local function at(sym, name, chk, fn)
  local pc = S[sym]
  return mem:install_read_tap(pc, pc, name, function(a, d)
    if a ~= cpu.state["PC"].value then return d end
    for off, v in pairs(chk) do
      if r(pc + off) ~= v then return d end
    end
    fn()
    return d
  end)
end
local function w16(v) return {[1] = v & 0xFF, [2] = v >> 8} end
local function w16at(off, v) return {[off] = v & 0xFF, [off + 1] = v >> 8} end
TREG = mem:install_write_tap(0x2C, 0x30, "ls_reg", function(a, d) if reg[a] then reg[a] = d end end)
T1 = at("BandL1Start", "ls1", w16(S.L1_SG), function()
  flush(band, "band"); band = {row = r(S.L1_SG), phase = phase(), scene = r(S.G_ZD0), sizes = {}}; pend = nil
end)
T2 = at("BandWL1", "ls2", w16(S.L1_SGX), function() pend = r(S.S_FL0) end)
T3 = at("BandWL1X", "ls3", w16(S.L1_SGX), function()
  if band and pend then band.sizes[#band.sizes + 1] = pend .. ":x" end
  pend = nil
end)
T4 = at("BandWEnd", "ls4", {[1] = 0, [2] = 0x91, [3] = S.ZP_P1}, function()
  if band and pend then band.sizes[#band.sizes + 1] = pend .. ":" .. (cpu.state["Y"].value + 2) end
  pend = nil
end)
T5 = at("TopSegStart", "ls5", w16at(2, S.S_BLPC), function() flush(top, "top"); top = nil end)
-- (a list counts where TpPlace places it, TpPlF: its entry fires again when
-- an interrupt lands on its first instruction, the opcode fetched again after
-- the RTI; and a rebuild starts wherever the row's pointers are all at their
-- pieces' starts too)
local TLET = {[0x00] = "A", [0x08] = "B", [0x10] = "C", [0x18] = "D", [0x20] = "E", [0x28] = "F"}
local tpend = nil
T6 = at("TpPlace", "ls6", w16(S.S_BLPC), function() tpend = r(S.S_EW) + 2 end)
T7 = at("TpPlF", "ls7", w16(S.TP_SGP), function()
  if not tpend then return end
  local row, used = r(S.TP_SG), 0
  for k = 0, 6 do
    local lo = S[string.format("TPS%s%d", TLET[row] or "A", k)]
    local v = r(S.TP_SGP + 2 * k) + 256 * r(S.TP_SGP + 2 * k + 1)
    if lo and lo > 0 and v >= lo and v < lo + 256 then used = used + v - lo end
  end
  if top and (used == 0 or top.row ~= row) then flush(top, "top"); top = nil end
  if not top then top = {row = row, phase = phase(), scene = r(S.G_ZD0), sizes = {}} end
  top.sizes[#top.sizes + 1] = tostring(tpend)
  tpend = nil
end)
local f = 0
local function dump()
  local o = io.open("listseq.log", "w")
  for k, n in pairs(count) do o:write(n .. " " .. k .. "\n") end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if f % 2000 == 0 or f == END then dump() end
end)
if not os.getenv("PLAYBACK") then dofile(os.getenv("PROBES") .. "/playkey.lua") end   -- (under port/replay.sh: the recording plays)
