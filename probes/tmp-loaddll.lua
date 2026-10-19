-- (debug) the DLL MARIA is given (DPPH/DPPL) while the tiles' loader runs
-- (L1TLoad to L1Load's end, at each scene's load): each frame inside, the
-- DLL's address and whether it is BLANK_DLL, to loaddll.log. Runs
-- playkey.lua (its env applies) unless NOPLAYKEY.
if not os.getenv("NOPLAYKEY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local o = io.open("loaddll.log", "w")
local dpph, dppl, inside, frame = 0, 0, false, 0
TLD1 = mem:install_write_tap(0x2C, 0x30, "ldpp", function(a, d)
  if a == 0x2C then dpph = d elseif a == 0x30 then dppl = d end
end)
TLD2 = mem:install_read_tap(S.L1Gen, S.L1Gen, "ldin", function(a, d)
  if a == cpu.state["PC"].value then inside = true; o:write(string.format("enter frame %d\n", frame)) end
end)
TLD3 = mem:install_read_tap(S.L1LoadNo, S.L1LoadNo, "ldout", function(a, d)
  if a == cpu.state["PC"].value and inside then inside = false; o:write(string.format("leave frame %d\n", frame)) end
end)
emu.register_frame_done(function()
  frame = frame + 1
  if inside then
    local dll = dpph * 256 + dppl
    o:write(string.format("frame %d DLL %04X %s\n", frame, dll, dll == S.BLANK_DLL and "blank" or "SHOWN"))
  end
  o:flush()
end)
