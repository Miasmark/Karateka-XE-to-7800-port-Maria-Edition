-- a recording played back: a screenshot every STEP frames from F0 to F1, with
-- the scene ($D0), the structure ($4C) and the view ($52, $50) to recsnap.log
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local function zp(x) return mem:read_u8(ZM[x]) end
local F0, F1, STEP = tonumber(os.getenv("F0") or "0"), tonumber(os.getenv("F1") or "20000"), tonumber(os.getenv("STEP") or "120")
local o = io.open("recsnap.log", "w")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f >= F0 and f <= F1 and (f - F0) % STEP == 0 then
    M.video:snapshot()
    o:write(string.format("%d D0 %d 4C %d 52 %d 50 %d\n", f, zp(0xD0), zp(0x4C), zp(0x52), zp(0x50))); o:flush()
  end
  if f > F1 then o:close(); M:exit() end
end)
