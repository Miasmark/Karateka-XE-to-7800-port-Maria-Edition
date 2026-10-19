-- (debug) playkey.lua, plus: CPU writes to pages $58-$63's first 16 bytes
-- (the front boxes' tables) while S_L1 is on, by address and PC, to
-- fgwrites.log at END - 5
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "300")
local cnt, f = {}, 0
TFG = mem:install_write_tap(tonumber(os.getenv("FGLO") or "5800", 16), tonumber(os.getenv("FGHI") or "63FF", 16), "fgw", function(a, d)
  if (not os.getenv("FGALL") and a & 0xFF >= 16) or mem:read_u8(S.S_L1) ~= 1 then return end
  local k = string.format("%04X pc %04X", a, cpu.state["PC"].value)
  cnt[k] = (cnt[k] or 0) + 1
end)
emu.register_frame_done(function()
  f = f + 1
  if f ~= END - 5 then return end
  local o = io.open("fgwrites.log", "w")
  local t = {}
  for k, v in pairs(cnt) do t[#t + 1] = k .. " " .. v end
  table.sort(t)
  o:write(table.concat(t, "\n") .. "\n")
  o:close()
end)
