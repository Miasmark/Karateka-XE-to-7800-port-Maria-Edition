-- (debug) a recording played on its own cart (-playback, EXTRA): a snapshot
-- every STEP frames (from FROM), and a line a STEP to recsnap.log: frame,
-- scene (G_ZD0), PC, S_BANK, S_SCENEBANK, the NMI count; exits at END
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local STEP = tonumber(os.getenv("STEP") or "30")
local FROM = tonumber(os.getenv("RFROM") or os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "11000")
local zp = {}
for l in io.lines(os.getenv("ZPMAP")) do local z, a = l:match("(%x+) (%x+)"); if z then zp[tonumber(z, 16)] = tonumber(a, 16) end end
local log = io.open("recsnap.log", "w")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f >= FROM and f % STEP == 0 then
    log:write(string.format("f%d D0=%02X PC=%04X BANK=%d SCB=%d NMI=%d\n", f, mem:read_u8(zp[0xD0]),
      cpu.state["PC"].value, mem:read_u8(sym.S_BANK), mem:read_u8(sym.S_SCENEBANK), mem:read_u8(sym.S_NMICOUNT)))
    log:flush()
    M.video:snapshot()
  end
  if f >= END then M:exit() end
end)
