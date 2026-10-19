-- reads of address ranges in one bank (FINDINGS "Level 1's page: the copies
-- no one reads"): RANGES (hex lo-hi, comma list), BANK (S_BANK's value: the
-- bank in the window); each read with that bank in, its PC, frame and flip
-- (the first 200, and a count by PC), to bankreads.log at the end. Runs
-- playkey.lua (its env applies) unless NOPLAY. END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local BANK = tonumber(os.getenv("BANK") or "1")
local END = tonumber(os.getenv("END") or "6000")
local f, n, bypc, first = 0, 0, {}, {}
local taps = {}
for lo, hi in (os.getenv("RANGES") or ""):gmatch("(%x+)-(%x+)") do
  taps[#taps + 1] = mem:install_read_tap(tonumber(lo, 16), tonumber(hi, 16), "br" .. lo, function(a, d)
    if mem:read_u8(S.S_BANK) ~= BANK then return d end
    local pc = cpu.state["PC"].value
    n = n + 1
    local k = string.format("%04X", pc)
    bypc[k] = (bypc[k] or 0) + 1
    if #first < 200 then first[#first + 1] = string.format("f%d flip %s $%04X by %04X D0 %02X", f, tostring(PLAYKEY_N), a, pc, mem:read_u8(0xD0)) end
    return d end)
end
BRTAPS = taps
emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    local o = io.open("bankreads.log", "w")
    o:write(string.format("%d reads with bank %d in\n", n, BANK))
    for k, c in pairs(bypc) do o:write(string.format("  by %s: %d\n", k, c)) end
    for _, l in ipairs(first) do o:write(l .. "\n") end
    o:close()
  end
end)
-- NOPLAY=1: a recording played back (no scripted player)
if not os.getenv("NOPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
