-- (debug) playkey.lua, plus: every CPU write into LO-HI (default module B's
-- RAM, $7A00-$7FFF) after frame F0 (default 0: the load's copy included,
-- F0=300 leaves it out), counted by the target and the writing PC, to
-- selfmod.log at END - 5 frames: the self-modifying stores
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local LO = tonumber(os.getenv("LO") or "7A00", 16)
local HI = tonumber(os.getenv("HI") or "7FFF", 16)
local F0 = tonumber(os.getenv("F0") or "0")
local END = tonumber(os.getenv("END") or "300")
local f, cnt = 0, {}
TSM = mem:install_write_tap(LO, HI, "selfm", function(a, d)
  if f < F0 then return end
  local k = string.format("%04X %04X", a, cpu.state["PC"].value)
  cnt[k] = (cnt[k] or 0) + 1
end)
RU_SM = emu.add_machine_frame_notifier(function()
  f = f + 1
  if f ~= END - 5 then return end
  local t = {}
  for k, n in pairs(cnt) do t[#t + 1] = {k, n} end
  table.sort(t, function(x, y) return x[1] < y[1] end)
  local o = io.open("selfmod.log", "w")
  for _, e in ipairs(t) do o:write(string.format("%s %d\n", e[1], e[2])) end
  o:close()
end)
