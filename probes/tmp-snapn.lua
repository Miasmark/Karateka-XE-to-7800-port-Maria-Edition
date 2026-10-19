-- (debug) a companion of p7800-stateplay.lua (SPALSO): snapshots of the
-- frames 1 to SNAPK after each flip in SNAPN (comma list, STATEPLAY_N)
local M = manager.machine
local want = {}
for t in (os.getenv("SNAPN") or ""):gmatch("%d+") do want[tonumber(t)] = true end
local K = tonumber(os.getenv("SNAPK") or "6")
local last, cnt = -1, 0
SNAPN_LOG = io.open("snaplist.txt", "w")   -- (each snapshot's flip and frame after it, in order)
emu.register_frame_done(function()
  local n = _G.STATEPLAY_N or -1
  if n ~= last then last, cnt = n, 0 else cnt = cnt + 1 end
  if want[n] and cnt >= (tonumber(os.getenv("SNAPK0") or "1")) and cnt <= K then
    M.video:snapshot()
    SNAPN_LOG:write(n .. " " .. cnt .. "\n"); SNAPN_LOG:flush()
  end
end)
