-- writes to the framebuffer pages' first 16 bytes (outside the buffers:
-- FINDINGS "The status bar as objects"), pages $44-$72, while the scripted
-- player (playkey.lua, with its settings) runs: each page/offset written,
-- by which PC, how often, to pageheads.log at the end
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local seen, order = {}, {}
PH = mem:install_write_tap(0x4400, 0x72FF, "pageheads", function(a, d)
  if a & 0xFF < 16 then
    local k = string.format("%04X PC=%04X", a, cpu.state["PC"].value)
    if not seen[k] then seen[k] = 0; order[#order + 1] = k end
    seen[k] = seen[k] + 1
  end
  return d end)
local frame = 0
local END = tonumber(os.getenv("END") or "300")
emu.register_frame_done(function()
  frame = frame + 1
  if frame == END - 1 then
    local o = io.open("pageheads.log", "w")
    for _, k in ipairs(order) do o:write(string.format("%s x%d\n", k, seen[k])) end
    o:write(string.format("%d frames, %d places\n", frame, #order))
    o:close()
  end
end)
