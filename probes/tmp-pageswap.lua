-- (debug) page switches: each CPU write to the bank window ($8000-$BFFF)
-- that changes the bank, with the frame, the lines since the frame's end, the instruction, the
-- display list pointer last written (DPPH $2C, DPPL $30) and the one the
-- frame began with (DPP when the last frame ended); a snapshot of that frame
-- and the next (SNAPMAX, default 40). To pageswap.log. ALSO: another probe.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local t0 = 0
local function line() return math.floor((M.time:as_double() - t0) * 60 * 262) end   -- (lines since the last frame's end)
local st = cpu.state
local MAX = tonumber(os.getenv("SNAPMAX") or "40")
local BLANK = tonumber(os.getenv("BLANK") or "0", 16)    -- (BLANK: the blank list; no snapshot for a switch under it)
local reg = {[0x2C] = 0, [0x30] = 0}
local cur, f, nsnap = -1, 0, 0
local fstart = 0
local want = {}
local log = io.open("pageswap.log", "w")
PS_T1 = mem:install_write_tap(0x2C, 0x30, "ps_reg", function(a, d) if reg[a] then reg[a] = d end end)
PS_T2 = mem:install_write_tap(0x8000, 0xBFFF, "ps_w", function(a, d)
  if d == cur then return end
  local pc = st["CURPC"] and st["CURPC"].value or st["PC"].value
  log:write(string.format("f%d line %d bank %02X->%02X pc %04X dpp %04X framedpp %04X\n", f, line(), cur & 0xFF, d,
                          pc, reg[0x2C] * 256 + reg[0x30], fstart))
  log:flush()
  cur = d
  if nsnap < MAX and not (fstart == BLANK and reg[0x2C] * 256 + reg[0x30] == BLANK) then want[f] = true; want[f + 1] = true; nsnap = nsnap + 1 end
end)
PS_F = emu.register_frame_done(function()
  if want[f] then
    M.video:snapshot()
    log:write(string.format("snap f%d\n", f))
  end
  f = f + 1
  t0 = M.time:as_double()
  fstart = reg[0x2C] * 256 + reg[0x30]
end)
if os.getenv("ALSO") then dofile(os.getenv("PROBES") .. "/" .. os.getenv("ALSO")) end
