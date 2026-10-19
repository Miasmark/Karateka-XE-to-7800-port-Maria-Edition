-- the largest $B6 + $B7 (player + foe health, the status bar's arrows) per
-- scene, and the frame and both values; to hpsum.log
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local END = tonumber(os.getenv("END") or "20000")
local best, f = {}, 0
emu.register_frame_done(function()
  f = f + 1
  local sc, p, e = mem:read_u8(0xD0), mem:read_u8(0xB6), mem:read_u8(0xB7)
  if sc <= 6 and (not best[sc] or p + e > best[sc][1]) then best[sc] = {p + e, f, p, e} end
  if f >= END then
    local o = io.open("hpsum.log", "w")
    for sc = 0, 6 do if best[sc] then o:write(string.format("scene %d: %d arrows (player %d, foe %d) at frame %d\n", sc, best[sc][1], best[sc][3], best[sc][4], best[sc][2])) end end
    o:close(); M:exit()
  end
end)
