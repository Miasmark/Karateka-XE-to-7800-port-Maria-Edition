-- (debug) playkey.lua, plus: at the end of the frame after flip K, memory
-- ranges (MEM: "lo-hi,lo-hi" hex) and DPPH/DPPL as written, to memdump.log
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local K = tonumber(os.getenv("K") or "220")
local dpp = {[0x2C] = 0, [0x30] = 0}
TMD = mem:install_write_tap(0x2C, 0x30, "mddpp", function(a, d) if a == 0x2C or a == 0x30 then dpp[a] = d end end)
local done = false
RU_MD = emu.add_machine_frame_notifier(function()
  if done or (PLAYKEY_N or 0) < K then return end
  done = true
  local o = io.open("memdump.log", "w")
  o:write(string.format("flip %d DLL %02X%02X\n", PLAYKEY_N, dpp[0x2C], dpp[0x30]))
  for lo, hi in (os.getenv("MEM") or ""):gmatch("(%x+)-(%x+)") do
    local a, b = tonumber(lo, 16), tonumber(hi, 16)
    local t = {}
    for x = a, b do t[#t + 1] = string.format("%02X", mem:read_u8(x)) end
    o:write(string.format("%04X: %s\n", a, table.concat(t, " ")))
  end
  o:close()
end)
