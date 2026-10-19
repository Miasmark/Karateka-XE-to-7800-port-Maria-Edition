-- (debug) a companion of p7800-stateplay.lua (SPALSO): in flips PFROM to
-- PTO, the calls of AkLook and FtEmitAk, AkLook's outcome (AKP_ON after it,
-- at FtPlain's entry), and AK_N of both buffers at each FtEmitAk, to
-- akcount.log at PTO; MAME exits
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
if not SYM_ADDR then dofile(os.getenv("PROBES") .. "/p7800-sym.lua") end
local S = SYM_ADDR
local FR = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local c = {look = 0, emit = 0, on = 0, off = 0}
local akn = {}
local function on() local n = _G.STATEPLAY_N or 0; return n >= FR and n <= TO end
AC_TAPS = {}
local function at(name, fn)
  local a = S[name]
  AC_TAPS[#AC_TAPS + 1] = mem:install_read_tap(a, a, "ac" .. name, function(ad, d)
    if on() and ad == cpu.state["PC"].value then fn() end
    return d
  end)
end
at("AkLook", function() c.look = c.look + 1 end)
at("FtEmitAk", function()
  c.emit = c.emit + 1
  local k = string.format("A %d B %d buf %d", mem:read_u8(S.AK_N), mem:read_u8(S.AK_N + 1), mem:read_u8(S.S_FBUF))
  akn[k] = (akn[k] or 0) + 1
end)
at("FtPlain", function()
  if mem:read_u8(S.AKP_ON) ~= 0 then c.on = c.on + 1 else c.off = c.off + 1 end
end)
emu.register_frame_done(function()
  if (_G.STATEPLAY_N or 0) > TO then
    local o = io.open("akcount.log", "w")
    o:write(string.format("AkLook %d FtEmitAk %d FtPlain with AKP_ON %d without %d\n", c.look, c.emit, c.on, c.off))
    for k, v in pairs(akn) do o:write(string.format("%5d %s\n", v, k)) end
    o:close()
    M:exit()
  end
end)
