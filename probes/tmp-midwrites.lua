-- (debug) playkey.lua, plus: every write to MARIA's registers ($20-$3F)
-- while S_L1 is on, counted by register, value, PC and the line estimated
-- from emulated time since the frame began (in groups of 8), to
-- midwrites.log at END - 5 frames. A colour or CHBASE write during the
-- visible lines changes the picture from that line on.
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "300")
local t0, fr = nil, 0
local cnt = {}
RU_MW = emu.add_machine_frame_notifier(function()
  t0 = M.time:as_double()
  fr = fr + 1
  if fr ~= END - 5 then return end
  local t = {}
  for k, n in pairs(cnt) do t[#t + 1] = {k, n} end
  table.sort(t, function(a, b) return a[1] < b[1] end)
  local o = io.open("midwrites.log", "w")
  for _, e in ipairs(t) do o:write(string.format("%s %d\n", e[1], e[2])) end
  o:close()
end)
TMW = mem:install_write_tap(0x20, 0x3F, "midw", function(a, d)
  if not t0 or (S.S_L1 and mem:read_u8(S.S_L1) ~= 1) then return end
  local line = math.floor((M.time:as_double() - t0) * 15734.26)
  local pc = cpu.state["PC"].value
  local k = string.format((os.getenv("VAL") and string.format("v %02X ", d) or "") .. "reg %02X pc %04X %-12s line %3d-", a, pc, SYM_NAME and SYM_NAME[pc] or "", os.getenv("FINE") and line or line // 8 * 8)
  cnt[k] = (cnt[k] or 0) + 1
end)
