-- one frame's palette writes (FINDINGS "The fighters as objects: speed"):
-- in the first frame after flip AT's display list change (as playkey.lua's
-- SNAPDL), each write to palettes 1 and 4 ($25-$27, $31-$33) with its
-- scanline, to palframe.log. Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
-- the scan line, estimated as p7800-colwrites.lua does (this MAME's screen
-- has no vpos)
local t0 = 0
local function line() return math.floor((M.time:as_double() - t0) * 59.92 * 263) end
local AT = tonumber(os.getenv("AT") or "1280")
local o = io.open("palframe.log", "w")
local dpp, at, wait, on, done = {[0x2C] = 0, [0x30] = 0}, nil, false, false, false
TW = mem:install_write_tap(0x25, 0x33, "pf", function(a, d)
  if a == 0x2C or a == 0x30 then
    dpp[a] = d
    if wait and dpp[0x2C] * 256 + dpp[0x30] ~= at then wait = false; on = true end
    return
  end
  if on and (a <= 0x27 or a >= 0x31) then
    o:write(string.format("line %3d $%02X = $%02X\n", line(), a, d))
  end
end)
emu.register_frame_done(function()
  t0 = M.time:as_double()
  if done then return end
  if on then
    if o:seek() > 0 or true then on = false; done = true; o:close() end
    return
  end
  if not wait and (PLAYKEY_N or 0) == AT then wait = true; at = dpp[0x2C] * 256 + dpp[0x30] end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
