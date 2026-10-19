-- from flip FROM to TO (playkey.lua's count; it runs, its env applies): when
-- the port's display routines run, by frame and scanline (counted from the frame end), to flipapply.log:
-- FrameGo (a new list chosen), BuildDll, TopFlip, TopRefreshF, and Apply
-- with a list pending (its DPPH:DPPL, and whether MARIA is in vertical
-- blank). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local t0 = 0                -- (the scanline from the time since the last frame end: 263 a frame)
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM, TO = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("TO") or "99999")
local o = io.open("flipapply.log", "w")
local f = 0
local function pc() return cpu.state["PC"].value end
local function on() local n = PLAYKEY_N or 0; return n >= FROM and n <= TO end
local function put(s) o:write(string.format("%d %d line %d: %s\n", f, PLAYKEY_N or 0, math.floor((M.time:as_double() - t0) * 59.92 * 263), s)) end
TAPS = {}
for _, name in ipairs({"FrameGo", "BuildDll", "TopFlip", "TopRefreshF", "Apply"}) do
  local a = S[name]
  TAPS[#TAPS + 1] = mem:install_read_tap(a, a, "fa" .. name, function(ad, d)
    if ad == pc() and on() then
      if name == "Apply" then
        if mem:read_u8(S.S_PEND) ~= 0 then
          put(string.format("Apply %02X%02X vblank %d", mem:read_u8(S.S_PDPPH), mem:read_u8(S.S_PDPPL),
            (mem:read_u8(0x28) & 0x80) ~= 0 and 1 or 0))
        end
      else
        put(name)
      end
    end
    return d end)
end
emu.register_frame_done(function() f = f + 1; if on() then put(string.format("frame end: $0AF6 %02X pend %d vwait %02X", mem:read_u8(S.G_L0AF6), mem:read_u8(S.S_PEND), S.S_VWAIT and mem:read_u8(S.S_VWAIT) or 0)) end; t0 = M.time:as_double(); o:flush() end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
