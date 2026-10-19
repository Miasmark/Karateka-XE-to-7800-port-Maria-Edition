-- how often each PC in PCS (name=hex,...) runs while bank BANK is in the
-- window (S_BANK), from frame FROM, to pcbank.log (every 100 frames: playkey may end the run
-- first). WITHPLAY: playkey.lua's input as well.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "300")
local BANK = tonumber(os.getenv("BANK") or "1")
local FROM = tonumber(os.getenv("FROM") or "0")
local cnt, names, f = {}, {}, 0
TAPS = {}
for name, h in (os.getenv("PCS") or ""):gmatch("(%w+)=(%x+)") do
  local a = tonumber(h, 16); cnt[name] = 0; names[#names + 1] = name
  TAPS[#TAPS + 1] = mem:install_read_tap(a, a, "pb" .. name, function(ad, d)
    if f >= FROM and ad == cpu.state["PC"].value and (BANK < 0 or mem:read_u8(S.S_BANK) == BANK) then cnt[name] = cnt[name] + 1 end
    return d end)
end
local function dump()
  local o = io.open("pcbank.log", "w")
  for _, n in ipairs(names) do o:write(string.format("%s %d\n", n, cnt[n])) end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if f % 100 == 0 then dump() end
  if f >= END then dump(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
