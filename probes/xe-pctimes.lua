-- the frames at which each PC in PCS (name=hex,...) runs, FROM-END; to
-- pctimes.log as "name frame" lines (port/runxe.sh or run7800.sh)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local f = 0
local o = io.open("pctimes.log", "w")
TAPS = {}
for name, h in (os.getenv("PCS") or ""):gmatch("(%w+)=(%x+)") do
  local a = tonumber(h, 16)
  TAPS[#TAPS + 1] = mem:install_read_tap(a, a, "pt" .. name, function(ad, d)
    if f >= FROM and ad == PCs.value then o:write(name .. " " .. f .. "\n") end
    return d end)
end
emu.register_frame_done(function() f = f + 1; if f >= END then o:close(); M:exit() end end)
