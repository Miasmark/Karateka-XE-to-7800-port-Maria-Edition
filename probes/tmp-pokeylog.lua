-- (debug) the game's POKEY writes (the port's shadow S_POKEY, $D200-$D20F as
-- the game wrote them) and the TIA's sound registers, a line a frame from
-- TFROM to END (exits), to pokey.log: frame, AUDF1-4/AUDC1-4 (shadow), AUDCTL,
-- then the TIA's C0 C1 F0 F1 V0 V1
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local P = sym.S_POKEY
local FROM = tonumber(os.getenv("TFROM") or "0")
local END = tonumber(os.getenv("END") or "6000")
local r = {0, 0, 0, 0, 0, 0}
POKEYLOG_TAP = mem:install_write_tap(0x15, 0x1A, "pokeylog", function(a, d) r[a - 0x15 + 1] = d end)
local log = io.open("pokey.log", "w")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f >= FROM then
    local s = string.format("%d P", f)
    for i = 0, 8 do s = s .. string.format(" %02X", mem:read_u8(P + i)) end
    s = s .. string.format("  T %02X %02X %02X %02X %02X %02X", r[1], r[2], r[3], r[4], r[5], r[6])
    log:write(s .. "\n")
  end
  if f >= END then log:close(); M:exit() end
end)
