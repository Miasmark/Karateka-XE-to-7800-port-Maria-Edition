-- (debug) the fighters' records around a camera cut (the user's ghost at the
-- first guard's gate): from FROM to END, each entry of the full clear
-- (ClearBufF), the buffer copy (CopyBufF), the fill's record check (FgRecF)
-- and the flip (TopFlip), with the buffer drawn ($07) and the records:
-- FR_V (4: A's two, B's two), FR_C0/FR_C1 (their columns), to ghost.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local zp = {}
for l in io.lines(os.getenv("ZPMAP")) do local z, a = l:match("(%x+) (%x+)"); if z then zp[tonumber(z, 16)] = tonumber(a, 16) end end
local FROM = tonumber(os.getenv("FROM") or "2080")
local END = tonumber(os.getenv("END") or "2240")
local log = io.open("ghost.log", "w")
local f = 0
local function recs()
  local s = ""
  for i = 0, 3 do
    s = s .. string.format(" %d:%d[%d-%d]", i, mem:read_u8(sym.FR_V + i), mem:read_u8(sym.FR_C0 + i), mem:read_u8(sym.FR_C1 + i))
  end
  return s
end
local taps = {}
for _, n in ipairs({"ClearBufF", "CopyBufF", "FgRecF", "TopFlip"}) do
  local a = sym[n]
  taps[#taps + 1] = mem:install_read_tap(a, a, "g" .. n, function(ad, d)
    if f >= FROM and ad == cpu.state["PC"].value then
      log:write(string.format("f%d %-9s $07=%02X%s\n", f, n, mem:read_u8(zp[0x07]), recs()))
    end
    return d
  end)
end
GHOST_TAPS = taps
emu.register_frame_done(function()
  f = f + 1
  if f >= END then log:close(); M:exit() end
end)
