-- (debug) AkLook's results (Akuma's and the hawk's poses pre-cut at the
-- load): at AkLookE, per set (L1_SET), AKP_ON (1 found, 0 copied as ever)
-- counted, the key (AKP_KEY) of each miss with its picture (STATEPLAY_N),
-- and the totals at each new picture, to akhit.log. A replay's companion.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local o = io.open("akhit.log", "w")
local tot, lastn = {}, nil
TAKH = mem:install_read_tap(sym.AkLookE, sym.AkLookE, "akh", function(a, d)
  if a ~= cpu.state["PC"].value or d ~= 0x60 then return end   -- (its RTS: bank 5)
  local r = function(x) return mem:read_u8(x) end
  if r(sym.S_L1) == 0 then return end
  local s, on = r(sym.L1_SET), r(sym.AKP_ON)
  local k = s .. ":" .. on
  tot[k] = (tot[k] or 0) + 1
  local n = _G.STATEPLAY_N or -1
  if on == 0 then
    local key = {}
    for i = 0, 5 do key[#key + 1] = string.format("%02X", r(sym.AKP_KEY + i)) end
    o:write(string.format("%d miss set %d %s\n", n, s, table.concat(key, " ")))
  end
  if n ~= lastn then
    lastn = n
    local t = {}
    for k2, v in pairs(tot) do t[#t + 1] = k2 .. "=" .. v end
    o:write(n .. " total " .. table.concat(t, " ") .. "\n")
    o:flush()
  end
end)
if emu.add_machine_stop_notifier then emu.add_machine_stop_notifier(function() o:close() end) end
