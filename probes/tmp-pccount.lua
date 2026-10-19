-- (debug) a companion of p7800-stateplay.lua (SPALSO): from frame PFROM to
-- PTO, how often the instruction at each address in PCS (hex, comma list)
-- runs, a line per frame, to pccount.log (the embrace's wait: how its loop's
-- passes a frame change with the build)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "999999")
local pcs = {}
for t in (os.getenv("PCS") or ""):gmatch("%x+") do pcs[#pcs + 1] = tonumber(t, 16) end
local cnt = {}
local log = io.open("pccount.log", "w")
local f = 0
local taps = {}
for i, a in ipairs(pcs) do
  cnt[i] = 0
  taps[#taps + 1] = mem:install_read_tap(a, a, "pc" .. i, function(ad, d)
    if ad == cpu.state["PC"].value then cnt[i] = cnt[i] + 1 end
    return d
  end)
end
PCC_TAPS = taps
emu.register_frame_done(function()
  f = f + 1
  if f >= FROM and f <= TO then
    local s = string.format("f%d", f)
    for i = 1, #pcs do s = s .. string.format(" %04X:%d", pcs[i], cnt[i]) end
    log:write(s .. "\n")
    log:flush()
  end
  for i = 1, #pcs do cnt[i] = 0 end
  if os.getenv("PSTOP") and f > TO then log:close(); M:exit() end   -- (PSTOP=1: MAME stops after PTO)
end)
if os.getenv("ALSO") then dofile(os.getenv("PROBES") .. "/" .. os.getenv("ALSO")) end
