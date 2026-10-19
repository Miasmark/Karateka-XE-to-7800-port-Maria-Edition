-- (debug) p7800-stateplay.lua's companion (SPALSO): the most instances each
-- level-1 buffer held (L1_N), to l1n.log when the run stops
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local mx = {0, 0}
local at = {0, 0}
RU_N = emu.add_machine_frame_notifier(function()
  if mem:read_u8(S.S_L1) ~= 1 or (_G.STATEPLAY_N or 0) < 2 or (_G.STATEPLAY_N or 0) > 630 then return end
  for b = 0, 1 do
    local n = mem:read_u8(S.L1_N + b)
    if n > mx[b + 1] then mx[b + 1] = n; at[b + 1] = _G.STATEPLAY_N or 0 end
  end
end)
RU_NS = emu.add_machine_stop_notifier(function()
  local o = io.open("l1n.log", "w")
  o:write(string.format("most instances: A %d (flip %d), B %d (flip %d)\n", mx[1], at[1], mx[2], at[2]))
  o:close()
end)
