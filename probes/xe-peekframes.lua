-- bytes LO-HI (hex) at the end of each frame in FRAMES (comma list), to
-- peek.log as "frame: hex..."; stops after the last (runxe.sh / run7800.sh)
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local LO, HI = tonumber(os.getenv("LO"), 16), tonumber(os.getenv("HI"), 16)
local want, last = {}, 0
for t in (os.getenv("FRAMES") or ""):gmatch("%d+") do local n = tonumber(t); want[n] = true; if n > last then last = n end end
local f = 0
local o = io.open("peek.log", "w")
emu.register_frame_done(function()
  f = f + 1
  if want[f] then
    local s = f .. ":"
    for a = LO, HI do s = s .. string.format(" %02X", mem:read_u8(a)) end
    o:write(s .. "\n")
  end
  if f >= last then o:close(); M:exit() end
end)
