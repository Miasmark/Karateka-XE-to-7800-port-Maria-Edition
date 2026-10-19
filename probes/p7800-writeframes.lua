-- writes to RAM WLO-WHI (hex): per writer PC, its first and last frame and
-- the lowest and highest address, to writeframes.log at frame END
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local END = tonumber(os.getenv("END") or "300")
local f, seen, order = 0, {}, {}
WF = mem:install_write_tap(tonumber(os.getenv("WLO"), 16), tonumber(os.getenv("WHI"), 16), "wf", function(a, d)
  local pc = cpu.state["PC"].value
  local s = seen[pc]
  if not s then s = {f, f, a, a, 0}; seen[pc] = s; order[#order + 1] = pc end
  s[2] = f; s[3] = math.min(s[3], a); s[4] = math.max(s[4], a); s[5] = s[5] + 1
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f == END then
    local o = io.open("writeframes.log", "w")
    for _, pc in ipairs(order) do local s = seen[pc]
      o:write(string.format("PC=%04X frames %d-%d $%04X-$%04X x%d\n", pc, s[1], s[2], s[3], s[4], s[5])) end
    o:close(); M:exit()
  end
end)
