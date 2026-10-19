-- reads of the addresses in ADDRS (hex, comma-separated; lo-hi for a range) while the bank in
-- the window is BANK (default: any), counted with the reading PC, to
-- readcount.log at END. WITHPLAY: playkey.lua's input as well.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "300")
local BANK = tonumber(os.getenv("BANK") or "-1")
local cnt, f = {}, 0
TAPS = {}
for h in (os.getenv("ADDRS") or ""):gmatch("[%x%-]+") do
  local lo, hi = h:match("^(%x+)%-(%x+)$")
  local a, b = tonumber(lo or h, 16), tonumber(hi or h, 16)
  TAPS[#TAPS + 1] = mem:install_read_tap(a, b, "rc" .. h, function(ad, d)
    if ad ~= cpu.state["PC"].value and (BANK < 0 or mem:read_u8(S.S_BANK) == BANK) then
      local k = string.format("$%04X from $%04X", ad, cpu.state["PC"].value)
      cnt[k] = (cnt[k] or 0) + 1
    end
    return d end)
end
emu.register_frame_done(function()
  f = f + 1
  if f >= END then
    local o = io.open("readcount.log", "w")
    for k, n in pairs(cnt) do o:write(k .. ": " .. n .. "\n") end
    o:write("done\n"); o:close(); M:exit()
  end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
