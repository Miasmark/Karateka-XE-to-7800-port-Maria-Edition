-- (debug) a companion of p7800-stateplay.lua (SPALSO): from flip PFROM to
-- PTO, each TopDel (the entry deleted: index X, its piece, left byte, kept
-- bytes, the caller's return), each TopEraseList (the fill's pixels and
-- rows, the buffer), each TopCover (the same) and each TopClear/TopCopy,
-- to topdel.log; MAME exits after PTO
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
if not SYM_ADDR then dofile(os.getenv("PROBES") .. "/p7800-sym.lua") end
local S = SYM_ADDR
local FR = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local o = io.open("topdel.log", "w")
local function r(a) return mem:read_u8(a) end
local function on() local n = _G.STATEPLAY_N or 0; return n >= FR and n <= TO end
local function ret()
  local sp = cpu.state["SP"].value & 0xFF
  return r(0x100 + ((sp + 1) & 0xFF)) + 256 * r(0x100 + ((sp + 2) & 0xFF)) + 1
end
TD_TAPS = {}
local taps = TD_TAPS
local function at(name, fn)
  local a = S[name]
  if not a then o:write("no symbol " .. name .. "\n"); return end
  taps[#taps + 1] = mem:install_read_tap(a, a, "td" .. name, function(ad, d)
    if on() and ad == cpu.state["PC"].value then fn() end
    return d
  end)
end
at("TopDel", function()
  local x = cpu.state["X"].value
  o:write(string.format("n%d Del X %d piece %d lx %d k %d-%d from %04X buf %d\n", _G.STATEPLAY_N, x,
    r(S.TOPLI + x), r(S.TOPLX + x), r(S.TOPLK0 + x), r(S.TOPLK1 + x), ret(), r(S.S_TBUF)))
end)
at("TopEraseList", function()
  o:write(string.format("n%d Erase px %d-%d rows %d-%d buf %d n %d,%d\n", _G.STATEPLAY_N, r(S.S_TB0), r(S.S_TB1),
    r(S.S_TF0), r(S.S_TF1), r(S.S_TBUF), r(S.TOPLN), r(S.TOPLN + 1)))
end)
at("TopCover", function()
  o:write(string.format("n%d Cover px %d-%d rows %d-%d buf %d from %04X\n", _G.STATEPLAY_N, r(S.S_TB0), r(S.S_TB1),
    r(S.S_TF0), r(S.S_TF1), r(S.S_TBUF), ret()))
end)
at("TopClear", function() o:write(string.format("n%d Clear\n", _G.STATEPLAY_N)) end)
at("TopCopy", function() o:write(string.format("n%d Copy\n", _G.STATEPLAY_N)) end)
emu.register_frame_done(function()
  if (_G.STATEPLAY_N or 0) > TO then o:close(); M:exit() end
end)
