-- (debug) Akuma's captured blits at each flip (TopFlip) from frame PFROM to
-- PTO: each buffer's AK_V, AK_N and its blits (image AK_HI/AK_LO, bank, column
-- AK_COL, row AK_ROW, shift AK_SH, flags AK_FL), to akdump.log; MAME stops
-- after PTO (Akuma's body following the player into the next rooms)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local FROM = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local MAX = 10
local log = io.open("akdump.log", "w")
local f = 0
local function r(n, i) return mem:read_u8(sym[n] + (i or 0)) end
AKD_TAP = mem:install_read_tap(sym.TopFlip, sym.TopFlip, "akd", function(ad, d)
  if f >= FROM and ad == cpu.state["PC"].value then
    local s = string.format("f%d", f)
    for b = 0, 1 do
      s = s .. string.format(" | %s V%d N%d:", b == 0 and "A" or "B", r("AK_V", b), r("AK_N", b))
      for k = 0, math.min(r("AK_N", b), MAX) - 1 do
        local i = b * MAX + k
        s = s .. string.format(" %02X%02X/%d c%d r%d s%d f%02X", r("AK_HI", i), r("AK_LO", i), r("AK_BK", i),
          r("AK_COL", i), r("AK_ROW", i), r("AK_SH", i), r("AK_FL", i))
      end
    end
    log:write(s .. "\n")
    log:flush()
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f > TO then log:close(); M:exit() end
end)
