-- (debug) band lists longer than their estimate: at BandWL1F (a piece found:
-- L1_SGK, its start ZP_P1 is set just after, the estimate S_FL0) and at
-- BandWEnd (Y + 2 the real size, ZP_P1 the list's start): lists whose real
-- size passes the estimate, and those whose end passes their piece's end
-- (L1S<row letter><k>E: a write past the piece). Counts, and the first 12
-- with the frame, row, piece, estimate, real size, start, the piece's end, the
-- zone (S_ZTN's and L1_SX). To bandover.log at each 1000th frame. Runs
-- playkey.lua; the no-rules MAME.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local function r(a) return mem:read_u8(a) end
local LET = {[0x00] = "A", [0x08] = "B", [0x10] = "C", [0x18] = "D", [0x20] = "E", [0x28] = "F"}
local f, pend = 0, nil
local nlong, nover, lists, first = 0, 0, 0, {}
local function at(sym, name, b1, b2, fn)
  local pc = S[sym]
  return mem:install_read_tap(pc, pc, name, function(a, d)
    if a == cpu.state["PC"].value and r(pc + 1) == b1 and (b2 == nil or r(pc + 2) == b2) then fn() end
    return d
  end)
end
-- BandWL1F: STX L1_SGK
T1 = at("BandWL1F", "bo1", S.L1_SGK & 0xFF, S.L1_SGK >> 8, function()
  pend = {est = r(S.S_FL0), row = r(S.L1_SG), k = cpu.state["X"].value // 2}
end)
-- BandWEnd: LDA #$00 / STA (ZP_P1),Y
T2 = at("BandWEnd", "bo2", 0x00, 0x91, function()
  if not pend then return end
  local real = cpu.state["Y"].value + 2
  local start = r(S.ZP_P1) + 256 * r(S.ZP_P1 + 1)
  local pe = S[string.format("L1S%s%dE", LET[pend.row] or "?", pend.k)] or 0
  lists = lists + 1
  local long, over = real > pend.est, start + real > pe
  if long then nlong = nlong + 1 end
  if over then nover = nover + 1 end
  if (long or over) and #first < 12 then
    first[#first + 1] = string.format("f%d row %02X piece %d est %d real %d at $%04X piece end $%04X sx %d%s",
      f, pend.row, pend.k, pend.est, real, start, pe, r(S.L1_SX), over and " PAST" or "")
  end
  pend = nil
end)
emu.register_frame_done(function()
  f = f + 1
  if f % 1000 == 0 then
    local o = io.open("bandover.log", "w")
    o:write(string.format("lists %d, longer than the estimate %d, past the piece %d\n", lists, nlong, nover))
    for _, s in ipairs(first) do o:write(s .. "\n") end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
