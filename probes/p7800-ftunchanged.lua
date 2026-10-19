-- how often an emit could be skipped whole (FINDINGS "The fighters as
-- objects: speed"): at each emit that makes objects (FtEmitDo, bank 5), the
-- buffer's two records (FR_V nonzero, $20 $21 $22 $50 $3E $36) and its
-- recorded front boxes (FGR_*, those of this picture, or the shown ones when
-- none were drawn) against the same buffer's last emit. Counts to
-- ftunchanged.log at the end. Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local function b(a) return mem:read_u8(a) end
local last, n, same, samerec, f = {}, 0, 0, 0, 0
T1 = mem:install_read_tap(S.FtEmitDo, S.FtEmitDo, "fu1", function(a, d)
  if a ~= cpu.state["PC"].value or b(S.S_BANK) ~= 5 then return d end
  local buf = b(S.S_FBUF)
  local r = {}
  for s = 0, 1 do
    local x = 2 * buf + s
    r[#r + 1] = b(S.FR_V + x) ~= 0 and string.format("%d,%d,%d,%d,%d,%d", b(S.FR_20 + x), b(S.FR_21 + x),
      b(S.FR_22 + x), b(S.FR_50 + x), b(S.FR_3E + x), b(S.FR_36 + x)) or "-"
  end
  local rec = table.concat(r, " ")
  local bx = {}
  local seen = b(S.FT_SEEN + buf) ~= 0
  local nb = seen and b(S.FGR_N + buf) or b(S.FG_NS + buf)
  for i = 0, nb - 1 do
    local k = 8 * buf + i
    if seen then
      bx[#bx + 1] = string.format("%d+%d,%d-%d", b(S.FGR_C0 + k), b(S.FGR_W + k), b(S.FGR_R0 + k), b(S.FGR_R1 + k))
    else
      bx[#bx + 1] = string.format("%d+%d,%d-%d", b(S.FG_C0 + k), b(S.FG_W + k), b(S.FG_R0 + k), b(S.FG_R1 + k))
    end
  end
  local all = rec .. " | " .. table.concat(bx, " ")
  n = n + 1
  if last[buf] and last[buf][1] == rec then samerec = samerec + 1 end
  if last[buf] and last[buf][2] == all then same = same + 1 end
  last[buf] = {rec, all}
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    local o = io.open("ftunchanged.log", "w")
    o:write(string.format("emits %d: records as the buffer's last %d, and its boxes too %d\n", n, samerec, same))
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
