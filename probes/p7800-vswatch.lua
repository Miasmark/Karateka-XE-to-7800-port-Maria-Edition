-- the vs fight in level 1's page: S_VS, S_SCID and zero-page $FF every
-- 100 frames, and how often $0900 (the vs fight's per-frame step, $9900 in
-- the scene page) runs, to vswatch.log. WITHPLAY: playkey.lua's input.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "300")
local f, n900 = 0, 0
T = mem:install_read_tap(0x9900, 0x9900, "v900", function(a, d)
  if a == cpu.state["PC"].value then n900 = n900 + 1 end
  return d end)
local o = io.open("vswatch.log", "w")
emu.register_frame_done(function()
  f = f + 1
  if f % 100 == 0 then
    o:write(string.format("f%d D0=%02X bank=%02X S_VS=%s S_SCID=%s FF=%02X $9900 runs %d\n", f,
      mem:read_u8(0xD0), mem:read_u8(S.S_SCENEBANK),
      S.S_VS and string.format("%02X", mem:read_u8(S.S_VS)) or "-",
      S.S_SCID and string.format("%02X", mem:read_u8(S.S_SCID)) or "-", mem:read_u8(0xFF), n900))
  end
  if f >= END then o:close(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
