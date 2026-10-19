-- RAM at the end of frame AT (default 300): console RAM $1800-$27FF and cart
-- RAM $4000-$7FFF, to mem<AT>.bin (8K then 16K); stops there
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local AT = tonumber(os.getenv("AT") or "300")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f == AT then
    local t = {}
    for a = 0x1800, 0x27FF do t[#t + 1] = string.char(mem:read_u8(a)) end
    for a = 0x4000, 0x7FFF do t[#t + 1] = string.char(mem:read_u8(a)) end
    local o = io.open(string.format("mem%d.bin", AT), "wb"); o:write(table.concat(t)); o:close()
    M:exit()
  end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end   -- (WITHPLAY=1: the scripted player drives)
