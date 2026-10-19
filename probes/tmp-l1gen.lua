-- (debug) level 1's generated windows: at TopLoadF after a load with S_L1
-- on (L1Load done), cart RAM $4000-$72FF to l1gen.bin, then exit
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local done = false
T = mem:install_read_tap(S.TopLoadF, S.TopLoadF, "l1g", function(a, d)
  if done or a ~= cpu.state["PC"].value or mem:read_u8(S.S_L1) ~= 1 then return d end
  done = true
  local t = {}
  for x = 0x4000, 0x72FF do t[#t + 1] = string.char(mem:read_u8(x)) end
  local o = io.open("l1gen.bin", "wb"); o:write(table.concat(t)); o:close()
  local f = io.open("l1gen.log", "w"); f:write(string.format("frame %d\n", M.screens[":screen"]:frame_number())); f:close()
  M:exit()
  return d
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
