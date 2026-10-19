-- (debug) playkey.lua (or NOPLAYKEY=1: as p7800-stateplay.lua's companion),
-- plus: every frame while S_L1 is on, each zone of the shown DLL's top
-- (lines 48-112): its list's bytes (to its end), the most per zone (by its
-- first line) and the most for all of them at once, to topsize.log at the
-- run's end
if not os.getenv("NOPLAYKEY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
if not SYM_ADDR then dofile(os.getenv("PROBES") .. "/p7800-sym.lua") end
local S = SYM_ADDR
local dpp = {[0x2C] = 0, [0x30] = 0}
TTS = mem:install_write_tap(0x2C, 0x30, "tsdpp", function(a, d)
  if a == 0x2C or a == 0x30 then dpp[a] = d end
end)
local most, all, fr = {}, 0, 0
local function bytes(a)
  local n = 0
  for k = 1, 40 do
    local c1 = mem:read_u8(a + n + 1)
    if c1 & 0x1F == 0 then
      if c1 == 0 then return n + 2 end
      n = n + 5
    else
      n = n + 4
    end
  end
  return n
end
RU_TS = emu.add_machine_frame_notifier(function()
  if not os.getenv("ANY") and mem:read_u8(S.S_L1) ~= 1 then return end
  fr = fr + 1
  local dll = dpp[0x2C] * 256 + dpp[0x30]
  local line, t = 0, 0
  for e = 0, 90 do
    local b0, hi, lo = mem:read_u8(dll + 3 * e), mem:read_u8(dll + 3 * e + 1), mem:read_u8(dll + 3 * e + 2)
    if line >= 48 and line <= 112 then
      local n = bytes(hi * 256 + lo)
      local k = string.format("%3d h%2d", line, (b0 & 15) + 1)
      if n > (most[k] or 0) then most[k] = n end
      t = t + n
    end
    line = line + (b0 & 15) + 1
    if line > 112 then break end
  end
  if t > all then all = t end
end)
RU_TSS = emu.add_machine_stop_notifier(function()
  local o = io.open("topsize.log", "w")
  o:write(string.format("level-1 frames %d; the top's lists at once: most %d bytes\n", fr, all))
  local t = {}
  for k in pairs(most) do t[#t + 1] = k end
  table.sort(t)
  for _, k in ipairs(t) do o:write(string.format("line %s: most %d bytes\n", k, most[k])) end
  o:close()
end)
