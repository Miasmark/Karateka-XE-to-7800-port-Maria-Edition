-- the TIA sound registers (AUDC0/1 $15/$16, AUDF0/1 $17/$18, AUDV0/1 $19/$1A)
-- as written, each change with playkey.lua's flip count, to tialog.log:
-- "flip reg value". Compared between builds by flips (the frames before play
-- vary with the BIOS's time). Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local o = io.open("tialog.log", "w")
local last = {}
TW = mem:install_write_tap(0x15, 0x1A, "tia", function(a, d)
  if last[a] ~= d then
    last[a] = d
    o:write(string.format("%d %02X %02X\n", PLAYKEY_N or 0, a, d))
  end
end)
emu.register_frame_done(function() o:flush() end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
