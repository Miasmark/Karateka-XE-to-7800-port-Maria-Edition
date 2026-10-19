-- (debug) console RAM $1800-$27FF at frame SNAPAT (default 3000) to ramsnap.bin
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local at, f = tonumber(os.getenv("SNAPAT") or "3000"), 0
emu.register_frame_done(function()
  f = f + 1
  if f == at then
    local t = {}
    for a = 0x1800, 0x27FF do t[#t + 1] = string.char(mem:read_u8(a)) end
    local o = io.open("ramsnap.bin", "wb"); o:write(table.concat(t)); o:close()
  end
end)
if not os.getenv("PLAYBACK") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
