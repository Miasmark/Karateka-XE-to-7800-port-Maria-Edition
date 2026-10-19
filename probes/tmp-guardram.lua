-- (debug) the game's RAM ($0000-$1FFF) each time an enemy comes on after none
-- (buffer A's enemy record FR_V+1 nonzero after GAP flips at zero), with the
-- frame and the scene (G_ZD0), to guardram.bin (a 16-byte header: frame, scene,
-- then the 8K) and guardram.log; MAME stops at PTO (finding the game's guard
-- counter, for the guards' belt colours)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local TO = tonumber(os.getenv("PTO") or "20000")
local GAP = tonumber(os.getenv("GAP") or "20")
local bin = io.open("guardram.bin", "wb")
local log = io.open("guardram.log", "w")
local f, zero = 0, 999
GR_TAP = mem:install_read_tap(sym.TopFlip, sym.TopFlip, "gr", function(ad, d)
  if ad == cpu.state["PC"].value then
    local v = mem:read_u8(sym.FR_V + 1) + mem:read_u8(sym.FR_V + 3)
    if v == 0 then
      zero = zero + 1
    else
      if zero >= GAP then
        local sc = mem:read_u8(sym.G_ZD0)
        log:write(string.format("f%d scene %d enemy on after %d flips\n", f, sc, zero))
        log:flush()
        bin:write(string.pack("<I4I4I4I4", f, sc, 0, 0))
        local t = {}
        for a = 0, 0x1FFF do t[#t + 1] = string.char(mem:read_u8(a)) end
        bin:write(table.concat(t))
        bin:flush()
      end
      zero = 0
    end
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f > TO then bin:close(); log:close(); M:exit() end
end)
