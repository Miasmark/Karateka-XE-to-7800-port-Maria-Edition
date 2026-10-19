-- writes to WLO-WHI (hex) from frame FROM: frame, address, value, PC, bank;
-- (MAX of them, default 60)
-- the first 60 to wwatch.log (then the run ends). WITHPLAY=1: playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local FROM = tonumber(os.getenv("FROM") or "0")
local f, n, o = 0, 0, io.open("wwatch.log", "w")
local MAX = tonumber(os.getenv("MAX") or "60")
WT = mem:install_write_tap(tonumber(os.getenv("WLO"), 16), tonumber(os.getenv("WHI"), 16), "ww", function(a, d)
  if f >= FROM and n < MAX then
    n = n + 1
    o:write(string.format("frame %d $%04X <- %02X PC $%04X bank %d\n", f, a, d, cpu.state["PC"].value,
      mem:read_u8(SYM_ADDR.S_BANK)))
    o:flush()
    if n == MAX then o:close(); M:exit() end
  end
  return d end)
emu.register_frame_done(function() f = f + 1 end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
