-- (debug) console RAM $1800-$27FF at frame AT (side effects off), to ramsnap.bin. Runs playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local AT = tonumber(os.getenv("AT") or "2000")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f == AT then
    local t = {}
    for a = 0x1800, 0x27FF do t[#t + 1] = string.char(mem:read_u8(a)) end
    local o = io.open("ramsnap.bin", "wb"); o:write(table.concat(t)); o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
