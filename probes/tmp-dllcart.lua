-- (debug) p7800-stateplay.lua's companion (SPALSO): at the end of every
-- frame while S_L1 is on, the shown DLL's zones (DPPH/DPPL as written) whose
-- display list is in cart RAM ($4000-$7FFF), by line range: the frames with
-- any, the most bytes' zones, to dllcart.log at the run's end (lines LO-HI,
-- default the band and bottom zones 113-193)
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local LO, HI = tonumber(os.getenv("DLO") or "113"), tonumber(os.getenv("DHI") or "193")
local dpp = {[0x2C] = 0, [0x30] = 0}
TDC = mem:install_write_tap(0x2C, 0x30, "dcdpp", function(a, d)
  if a == 0x2C or a == 0x30 then dpp[a] = d end
end)
local frames, bad, worst, at, seen = 0, 0, 0, 0, {}
RU_DC = emu.add_machine_frame_notifier(function()
  if not os.getenv("ANY") and mem:read_u8(S.S_L1) ~= 1 then return end
  if os.getenv("ANY") and _G.PLAYKEY_N and _G.PLAYKEY_N < tonumber(os.getenv("FROMFLIP") or "0") then return end
  frames = frames + 1
  local dll = dpp[0x2C] * 256 + dpp[0x30]
  local line, n = 0, 0
  for e = 0, 90 do
    local b0, hi, lo = mem:read_u8(dll + 3 * e), mem:read_u8(dll + 3 * e + 1), mem:read_u8(dll + 3 * e + 2)
    local h = (b0 & 15) + 1
    if line >= LO and line <= HI and hi >= 0x40 and hi < 0x80 then
      n = n + 1
      seen[string.format("%02X%02X", hi, lo)] = true
    end
    line = line + h
    if line >= 243 then break end           -- (DLL_LINES: MARIA reads no further)
  end
  if n > 0 then bad = bad + 1 end
  if n > worst then worst = n; at = _G.STATEPLAY_N or 0 end
end)
RU_DCS = emu.add_machine_stop_notifier(function()
  local o = io.open("dllcart.log", "w")
  local t = {}
  for k in pairs(seen) do t[#t + 1] = k end
  table.sort(t)
  o:write(string.format("level-1 frames %d; with a band or bottom zone's list in cart RAM %d; most such zones %d (flip %d); lists %s\n",
    frames, bad, worst, at, table.concat(t, " ")))
  o:close()
end)
