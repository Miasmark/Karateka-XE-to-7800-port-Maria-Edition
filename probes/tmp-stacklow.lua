-- (debug) a companion of p7800-stateplay.lua (SPALSO): the lowest address
-- written in the stack page ($0140-$01FF and its mirror $2140-$21FF), with
-- the frame, SP and PC of that write, to stacklow.log at the run's end
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local f, low, at = 0, 0x200, ""
local function tap(a, d)
  local o = a & 0x1FF
  if f >= 300 and o < low then
    low = o
    at = string.format("f%d SP %02X PC %04X addr %04X", f, cpu.state["SP"].value & 0xFF, cpu.state["PC"].value, a)
  end
end
SL1 = mem:install_write_tap(0x0140, 0x01FF, "stl1", tap)
SL2 = mem:install_write_tap(0x2140, 0x21FF, "stl2", tap)
emu.register_frame_done(function()
  f = f + 1
  if f % 1000 == 0 or f > 18800 then
    local o = io.open("stacklow.log", "w")
    o:write(string.format("frames %d lowest $%03X %s\n", f, low, at))
    o:close()
  end
end)
