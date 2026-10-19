-- the original during a recording: a screenshot every STEP frames from F0 to
-- F1 with $4C, $52, $50 to recsnap.log (CHEAT: the recording's aid script)
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
local F0, F1, STEP = tonumber(os.getenv("F0") or "0"), tonumber(os.getenv("F1") or "12000"), tonumber(os.getenv("STEP") or "200")
local o = io.open("recsnap.log", "w")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f >= F0 and f <= F1 and (f - F0) % STEP == 0 then
    M.video:snapshot()
    o:write(string.format("%d 4C %d 52 %d 50 %d\n", f, mem:read_u8(0x4C), mem:read_u8(0x52), mem:read_u8(0x50))); o:flush()
  end
  if f > F1 then o:close(); M:exit() end
end)
