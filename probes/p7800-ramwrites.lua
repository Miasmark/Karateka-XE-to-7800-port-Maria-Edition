-- writes to RAM WLO-WHI (hex env vars) while the scripted player
-- (playkey.lua, with its settings) runs: each address written, by which PC,
-- how often, in first-write order, to pageheads.log at the end (as
-- p7800-pageheads.lua; writes before the cartridge's boot clear, PC $E156/
-- $E159, are the BIOS's)
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local seen, order = {}, {}
PH = mem:install_write_tap(tonumber(os.getenv("WLO"),16), tonumber(os.getenv("WHI"),16), "pageheads", function(a, d)
  if true then
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
