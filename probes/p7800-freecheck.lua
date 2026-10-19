-- the free-RAM ledger checked (layout7800.FREE_RAM, as the build wrote it
-- beside the symbol file: karateka7800.free): every write there after the
-- boot's clear (ClrRam-ClrCart's loop; before it, the BIOS's) is logged with its frame and PC, to
-- freecheck.log at frame END (the first 40, and the count). The scripted
-- player (playkey.lua, its env applies) drives the game.
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
if not SYM_ADDR then dofile(os.getenv("PROBES") .. "/p7800-sym.lua") end
local c0, c1 = SYM_ADDR.ClrRam, SYM_ADDR.ClrCart + 16
local ENDF = tonumber(os.getenv("END") or "300")
local f, n, bad, booted = 0, 0, {}, false
FC = {}
for line in io.lines((os.getenv("SYM"):gsub("%.sym$", ".free"))) do
  local lo, hi = line:match("^(%x+) (%x+)")
  if lo then
    n = n + 1
    FC[#FC + 1] = mem:install_write_tap(tonumber(lo, 16), tonumber(hi, 16), "free" .. n, function(a, d)
      local pc = cpu.state["PC"].value
      if pc >= c0 and pc < c1 then booted = true
      elseif booted then
        bad[#bad + 1] = string.format("frame %d $%04X <- %02X at PC $%04X", f, a, d, pc)
      end
      return d end)
  end
end
emu.register_frame_done(function()
  f = f + 1
  if f == ENDF - 1 then
    local o = io.open("freecheck.log", "w")
    o:write(string.format("%d ranges, %d frames: %d writes after the boot's clear\n", n, f, #bad))
    for i = 1, math.min(40, #bad) do o:write(bad[i] .. "\n") end
    o:close()
  end
end)
