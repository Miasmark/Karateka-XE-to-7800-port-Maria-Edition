-- (debug) RAM from LO to HI (hex) at frame F to ramdump.bin
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local F, LO, HI = tonumber(os.getenv("F") or "600"), tonumber(os.getenv("LO"), 16), tonumber(os.getenv("HI"), 16)
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f == F then
    local t = {}
    for a = LO, HI do t[#t + 1] = string.char(mem:read_u8(a)) end
    local o = io.open("ramdump.bin", "wb"); o:write(table.concat(t)); o:close()
    M:exit()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
