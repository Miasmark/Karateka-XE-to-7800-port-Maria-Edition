-- (debug) playkey.lua, plus: every frame while S_L1 is on, the screen's
-- pixel at (X, Y) against (X, Y + 2) (the cliff's first stripe line and
-- the next: the band's colour split lands between the sky and them):
-- frames where both are drawn (not black) and differ, to striperow.log at
-- END - 5 frames
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local S = SYM_ADDR
local scr = M.screens[":screen"]
local X, Y = tonumber(os.getenv("PX") or "8"), tonumber(os.getenv("PY") or "121")
local END = tonumber(os.getenv("END") or "300")
local PCOL = os.getenv("PCOL") and tonumber(os.getenv("PCOL"), 16)
local f, n, both, diff, first = 0, 0, 0, 0, {}
RU_SR = emu.add_machine_frame_notifier(function()
  f = f + 1
  if f == END - 5 then
    local o = io.open("striperow.log", "w")
    o:write(string.format("level-1 frames %d; both lines drawn %d; differing %d; first at frames %s\n",
      n, both, diff, table.concat(first, " ")))
    o:close()
  end
  if (S.S_L1 and mem:read_u8(S.S_L1) ~= 1) then return end
  n = n + 1
  if n == 300 then
    local o = io.open("column.log", "w")
    local ok, err = pcall(function() return scr:pixel(1, 1) end)
    o:write("pixel call: " .. tostring(ok) .. " " .. tostring(err) .. "\n")
    local w, h = 320, 262
    o:write(string.format("size %d x %d\n", w, h))
    for y = 0, h - 1 do o:write(string.format("%d %06X %06X\n", y, scr:pixel(X, y) & 0xFFFFFF, scr:pixel(X + 40, y) & 0xFFFFFF)) end
    o:close()
  end
  local a, b = scr:pixel(X, Y) & 0xFFFFFF, scr:pixel(X, Y + 2) & 0xFFFFFF
  if PCOL then                  -- (PCOL=rrggbb: frames where (X, Y) is that colour)
    if a == PCOL then
      diff = diff + 1
      if #first < 20 then first[#first + 1] = tostring(f) end
    end
  elseif a ~= 0 and b ~= 0 then
    both = both + 1
    if a ~= b then
      diff = diff + 1
      if #first < 20 then first[#first + 1] = string.format("%d(%06X/%06X)", f, a, b) end
    end
  end
end)
