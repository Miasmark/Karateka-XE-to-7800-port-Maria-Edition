-- the frames at which the routines in NAMES (comma-separated symbols, from
-- SYM) are entered, from frame FROM, to calltimes.log. ALSO: another probe.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local FROM = tonumber(os.getenv("FROM") or "0")
local f, o = 0, io.open("calltimes.log", "w")
TAPS = {}
for name in (os.getenv("NAMES") or ""):gmatch("[%w_]+") do
  local a = SYM_ADDR[name]
  if a then
    TAPS[#TAPS + 1] = mem:install_read_tap(a, a, "ct" .. name, function(ad, d)
      if f >= FROM and ad == cpu.state["PC"].value then o:write(string.format("%d %s\n", f, name)); o:flush() end
      return d end)
  end
end
local END = tonumber(os.getenv("END") or "0")
emu.register_frame_done(function()
  f = f + 1
  if END > 0 and f >= END then o:close(); M:exit() end     -- (END: the run ends there)
end)
if os.getenv("ALSO") then dofile(os.getenv("PROBES") .. "/" .. os.getenv("ALSO")) end
