-- (debug) p7800-stateplay.lua's companion (SPALSO): a snapshot at the end
-- of every frame while the flip count (_G.STATEPLAY_N) is F0-F1, and each
-- frame's number, flip and DPPH/DPPL (the list shown) to snapframes.log
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local F0, F1 = tonumber(os.getenv("F0") or "204"), tonumber(os.getenv("F1") or "206")
-- FLIPS: a comma list of flips instead (each one's frames)
local FL = {}
for t in (os.getenv("FLIPS") or ""):gmatch("%d+") do FL[tonumber(t)] = true end
local any = next(FL) ~= nil
local o = io.open("snapframes.log", "w")
local dpp = {[0x2C] = 0, [0x30] = 0}
TSF = mem:install_write_tap(0x2C, 0x30, "sfdpp", function(a, d)
  if a == 0x2C or a == 0x30 then dpp[a] = d end
end)
local fr = 0
RU_SF = emu.add_machine_frame_notifier(function()
  fr = fr + 1
  local n = _G.STATEPLAY_N or 0
  if (any and FL[n]) or (not any and n >= F0 and n <= F1) then
    M.video:snapshot()
    o:write(string.format("frame %d flip %d DLL %02X%02X\n", fr, n, dpp[0x2C], dpp[0x30]))
    o:flush()
  end
end)
