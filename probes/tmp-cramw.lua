-- (debug) the CPU's writes to cart RAM ($4000-$7FFF) during a replay: per
-- page and writing PC (with the bank in $8000-$BFFF, BANKSEL's last write),
-- the writes and the pictures (STATEPLAY_N) they fall in, to cramw.log at
-- each 100th picture and at the end. A replay's companion.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local cnt, pics, lastp = {}, {}, {}
local function dump()
  local o = io.open("cramw.log", "w")
  local ks = {}
  for k in pairs(cnt) do ks[#ks + 1] = k end
  table.sort(ks)
  for _, k in ipairs(ks) do o:write(string.format("%s %d %d\n", k, cnt[k], pics[k])) end
  o:close()
end
local lastdump = 0
TCRW = mem:install_write_tap(0x4000, 0x7FFF, "crw", function(a, d)
  local n = _G.STATEPLAY_N or -1
  local k = string.format("%02X %04X", a >> 8, cpu.state["PC"].value)
  cnt[k] = (cnt[k] or 0) + 1
  if lastp[k] ~= n then lastp[k] = n; pics[k] = (pics[k] or 0) + 1 end
  if n >= lastdump + 100 then lastdump = n; dump() end
end)
if emu.add_machine_stop_notifier then emu.add_machine_stop_notifier(dump) end
