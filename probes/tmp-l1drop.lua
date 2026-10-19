-- (debug) a companion of p7800-stateplay.lua (SPALSO): each time L1PartDd
-- drops an entry (its L1PartDx runs: an opcode fetch there), the flip
-- (STATEPLAY_N) and the scene ($D0), counted to l1drop.log (FINDINGS
-- "Akuma's red")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local AT = sym.L1PartDx
local cnt, scn = {}, {}
L1DROP_TAP = mem:install_read_tap(AT, AT, "l1drop", function(a, d)
  if cpu.state["PC"].value == AT then
    local f = _G.STATEPLAY_N or -1
    cnt[f] = (cnt[f] or 0) + 1
    scn[f] = mem:read_u8(sym.G_ZD0)
  end
  return d
end)
emu.register_frame_done(function()
  if (_G.STATEPLAY_N or 0) % 50 == 0 then
    local o = io.open("l1drop.log", "w")
    local ks = {}
    for k in pairs(cnt) do ks[#ks + 1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do o:write(string.format("flip %d scene %d drops %d\n", k, scn[k], cnt[k])) end
    o:close()
  end
end)
