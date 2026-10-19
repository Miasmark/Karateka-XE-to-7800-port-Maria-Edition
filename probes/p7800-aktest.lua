-- Akuma's capture tested on a guard (FINDINGS "Akuma as objects"): at each
-- enemy record (FRecDone with X odd and FT_IN 1), the enemy is turned into
-- an Akuma: FT_IN 2, its record off, the buffer's capture started (AK_N 0,
-- AK_V 2) and the captured pages widened to the art bank's ($80-$BF), so
-- bank 15's blits of the guard's upper body and lower sprite are captured
-- (AkCap) and emitted as Akuma's (FtEmitAk) instead of as a fighter's. The
-- lower body's mask isn't drawn for a guard ($AA54), so its black is
-- missing. Counts to aktest.log; runs playkey.lua (its env applies: SNAPK,
-- SNAPDL). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local function b(a) return mem:read_u8(a) end
local function w(a, v) mem:write_u8(a, v) end
local n, caps, f = 0, 0, 0
T1 = mem:install_read_tap(S.FRecDone, S.FRecDone, "ak1", function(a, d)
  if a ~= cpu.state["PC"].value or b(S.S_GLYIN) ~= 0 then return d end
  local x = cpu.state["X"].value
  if x % 2 == 1 and b(S.FT_IN) == 1 then
    local buf = x // 2
    w(S.FT_IN, 2); w(S.FR_V + x, 0)
    w(S.AK_N + buf, 0); w(S.AK_V + buf, 2)
    w(S.AK_PG0, 0x80); w(S.AK_PG1, 0xBF)
    n = n + 1
  end
  return d end)
T2 = mem:install_read_tap(S.AkCapK, S.AkCapK, "ak2", function(a, d)
  if a == cpu.state["PC"].value then caps = caps + 1 end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    local o = io.open("aktest.log", "w")
    o:write(string.format("enemies turned %d, blits captured %d\n", n, caps))
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
