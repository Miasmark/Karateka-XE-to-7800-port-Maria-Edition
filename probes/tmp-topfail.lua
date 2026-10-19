-- (debug) the top lists that find no piece: at TopEmitNone with S_EW not 0
-- (a counted list, TpPlace found no room: the zone gets DL_EMPTY), a count
-- by phase and, the first ten in play, the frame, the row (TP_SG), the list's
-- size and the pieces' next bytes (TP_SGP). To topfail.log at each 1000th
-- frame. Runs playkey.lua; the no-rules MAME (cart RAM read in a tap).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local function r(a) return mem:read_u8(a) end
local reg = {[0x2C] = 0, [0x30] = 0}
local f, n, first = 0, {L = 0, T = 0, P = 0}, {}
TREG = mem:install_write_tap(0x2C, 0x30, "tf_reg", function(a, d) if reg[a] then reg[a] = d end end)
TF = mem:install_read_tap(S.TopEmitNone, S.TopEmitNone, "tf", function(a, d)
  if a ~= cpu.state["PC"].value or r(S.S_EW) == 0 then return d end
  if r(a + 1) ~= (S.DL_EMPTY & 0xFF) then return d end   -- (LDA #<DL_EMPTY: this bank's)
  local ph = "P"
  if reg[0x2C] * 256 + reg[0x30] == S.BLANK_DLL then ph = "L"
  elseif r(S.S_STORY) ~= 0 or r(S.S_TITLEA) ~= 0 or r(S.S_TITLEB) ~= 0 then ph = "T" end
  n[ph] = n[ph] + 1
  if ph == "P" and #first < 10 then
    local t = {}
    for k = 0, 6 do t[#t + 1] = string.format("%02X%02X", r(S.TP_SGP + 2 * k + 1), r(S.TP_SGP + 2 * k)) end
    first[#first + 1] = string.format("f%d row %02X size %d ptrs %s", f, r(S.TP_SG), r(S.S_EW) + 2, table.concat(t, " "))
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f % 1000 == 0 then
    local o = io.open("topfail.log", "w")
    o:write(string.format("fails: load %d, text %d, play %d\n", n.L, n.T, n.P))
    for _, s in ipairs(first) do o:write(s .. "\n") end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
