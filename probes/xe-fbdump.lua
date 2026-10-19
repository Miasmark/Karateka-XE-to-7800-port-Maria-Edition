-- the original's two framebuffers at the end of each frame in FRAMES
-- (comma list): fb<frame>.bin = buffer A ($4808, 153 rows x 40) then B
-- ($3010), 12,240 bytes; stops after the last (port/runxe.sh)
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
local want, last = {}, 0
for t in (os.getenv("FRAMES") or ""):gmatch("%d+") do local n = tonumber(t); want[n] = true; if n > last then last = n end end
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if want[f] then
    local t = {}
    for _, base in ipairs({0x4808, 0x3010}) do
      for i = 0, 153 * 40 - 1 do t[#t + 1] = string.char(mem:read_u8(base + i)) end
    end
    local o = io.open("fb" .. f .. ".bin", "wb"); o:write(table.concat(t)); o:close()
  end
  if f >= last then M:exit() end
end)
