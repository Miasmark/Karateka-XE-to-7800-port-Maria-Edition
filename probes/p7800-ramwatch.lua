-- which bytes in LO-HI (hex) are ever written, END frames: the written
-- addresses as ranges, with a writer PC each; to ramwatch.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local LO, HI = tonumber(os.getenv("LO"), 16), tonumber(os.getenv("HI"), 16)
local END = tonumber(os.getenv("END") or "20000")
local seen = {}
local FROM = tonumber(os.getenv("FROM") or "0")   -- (writes before FROM not counted: the BIOS)
local f = 0
W = mem:install_write_tap(LO, HI, "rw", function(a, d) if f >= FROM and not seen[a] then seen[a] = cpu.state["PC"].value end; return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then
    local o = io.open("ramwatch.log", "w")
    local a = LO
    while a <= HI do
      if seen[a] then
        local b = a
        while b + 1 <= HI and seen[b + 1] do b = b + 1 end
        o:write(string.format("$%04X-$%04X written (first by PC $%04X)\n", a, b, seen[a]))
        a = b + 1
      else a = a + 1 end
    end
    o:close(); M:exit()
  end
end)
