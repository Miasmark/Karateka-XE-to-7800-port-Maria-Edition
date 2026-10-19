-- (debug) the machine's memory shares and regions with their sizes, to
-- shares.log at frame 60, then exit
local M = manager.machine
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f ~= 60 then return end
  local o = io.open("shares.log", "w")
  for k, v in pairs(M.memory.shares) do o:write(string.format("share %s %d\n", k, v.size)) end
  for k, v in pairs(M.memory.regions) do o:write(string.format("region %s %d\n", k, v.size)) end
  o:close()
  M:exit()
end)
