-- (debug) writes to the addresses in WADDR (hex, comma list) from frame
-- PFROM to PTO: frame, address, value, instruction, to wwatch.log; MAME stops
-- after PTO (the embrace's wait flag)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local log = io.open("wwatch.log", "w")
local f = 0
local taps = {}
for t in (os.getenv("WADDR") or ""):gmatch("%x+") do
  local a = tonumber(t, 16)
  taps[#taps + 1] = mem:install_write_tap(a, a, "ww" .. t, function(ad, d)
    if f >= FROM then
      local pc = cpu.state["CURPC"] and cpu.state["CURPC"].value or cpu.state["PC"].value
      log:write(string.format("f%d %04X=%02X pc %04X\n", f, ad, d, pc))
    end
  end)
end
WW_TAPS = taps
emu.register_frame_done(function()
  f = f + 1
  if f > TO then log:close(); M:exit() end
end)
