-- the game's zero page (XEGS $00-$FE through the build's map, ZPMAP) and
-- $D0 every EVERY frames (default 30) to zptrace.log, a snapshot every
-- SNAPEVERY frames (default none); for comparing two builds under the same
-- recorded input (EXTRA="-input_directory ... -playback ...").
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local END = tonumber(os.getenv("END") or "300")
local EVERY = tonumber(os.getenv("EVERY") or "30")
local SNAP = tonumber(os.getenv("SNAPEVERY") or "0")
local ZMAP = {}
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZMAP[tonumber(z, 16)] = tonumber(t, 16) end
end
local o, f = io.open("zptrace.log", "w"), 0
emu.register_frame_done(function()
  f = f + 1
  if f % EVERY == 0 then
    local t = {}
    for z = 0, 0xFE do t[#t + 1] = string.format("%02X", mem:read_u8(ZMAP[z])) end
    o:write(string.format("f%d %s\n", f, table.concat(t, " ")))
  end
  if SNAP > 0 and f % SNAP == 0 then M.video:snapshot() end
  if f >= END then o:close(); M:exit() end
end)
