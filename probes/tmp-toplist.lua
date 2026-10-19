-- (debug) a companion of p7800-stateplay.lua (SPALSO): at the flips in
-- TFLIPS (STATEPLAY_N), DF frames after, both buffers' top lists (TOPLN,
-- each entry's piece TOPLI, left pixel TOPLX, bytes TOPLK0-TOPLK1) and the
-- game's view ($52/$50), to toplist.log (FINDINGS "Level 2's windows")
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local want = {}
for t in (os.getenv("TFLIPS") or ""):gmatch("%d+") do want[tonumber(t)] = true end
local DF = tonumber(os.getenv("DF") or "2")
local MAX = 28
local log = io.open("toplist.log", "w")
local last, cnt = -1, 0
local function r(a) return mem:read_u8(a) end
emu.register_frame_done(function()
  local n = _G.STATEPLAY_N or -1
  if n ~= last then last, cnt = n, 0 else cnt = cnt + 1 end
  if not (want[n] and cnt == DF) then return end
  log:write(string.format("flip %d $52 %02X $50 %02X\n", n, r(0xD2), r(0xD0 - 0x80)))
  for b = 0, 1 do
    local k = r(sym.TOPLN + b)
    local s = {}
    for i = 0, k - 1 do
      local e = b * MAX + i
      s[#s + 1] = string.format("%d@%d[%d-%d]", r(sym.TOPLI + e), r(sym.TOPLX + e), r(sym.TOPLK0 + e), r(sym.TOPLK1 + e))
    end
    log:write(string.format("  %s n%d %s\n", b == 0 and "A" or "B", k, table.concat(s, " ")))
  end
  log:flush()
end)
