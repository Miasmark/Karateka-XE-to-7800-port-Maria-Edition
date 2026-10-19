-- the bytes LO-HI (hex) at the end of frame AT, to dumpram.bin (raw), then the
-- run ends. Runs playkey.lua (its env applies).
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local LO, HI = tonumber(os.getenv("LO"), 16), tonumber(os.getenv("HI"), 16)
local AT = tonumber(os.getenv("AT") or "1000")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f == AT then
    local o = io.open("dumpram.bin", "wb")
    for a = LO, HI do o:write(string.char(mem:read_u8(a))) end
    o:close()
    M:exit()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
