-- (debug) playkey.lua, plus: from frame F0 to F1, per frame: the NMIs
-- taken (opcode fetches of NMI_STUB's first byte, in console RAM), S_FRAMES,
-- DPPH/DPPL as written, PLAYKEY_N, to nmicount.log
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = SYM_ADDR
local F0, F1 = tonumber(os.getenv("F0") or "3600"), tonumber(os.getenv("F1") or "3900")
local f, n = 0, 0
local dpp = {[0x2C] = 0, [0x30] = 0}
TNC0 = mem:install_write_tap(0x2C, 0x30, "ncdpp", function(a, d)
  if a == 0x2C or a == 0x30 then dpp[a] = d end
end)
TNC = mem:install_read_tap(S.NMI_STUB, S.NMI_STUB, "nmic", function(a, d)
  if cpu.state["PC"].value == a then n = n + 1 end
  return d
end)
local o = io.open("nmicount.log", "w")
RU_NC = emu.add_machine_frame_notifier(function()
  f = f + 1
  if f >= F0 and f <= F1 then
    o:write(string.format("f%d nmis %d frames %d dll %02X%02X flip %d\n", f, n, mem:read_u8(S.S_FRAMES),
      dpp[0x2C], dpp[0x30], _G.PLAYKEY_N or 0))
    if f == F1 then o:close() end
  end
  n = 0
end)
