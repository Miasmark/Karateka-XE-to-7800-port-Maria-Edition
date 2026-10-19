-- the fighter-box erase decisions (FINDINGS "The fighter-box fills dropped"): at each
-- write of S_ERS, the erase (X odd: the enemy's), the game's $4D, $E5, $2C, $44, the
-- buffer, FT_DRW and the decision, counted, to ers.log at END. FROM frame.
-- Runs playkey.lua; ZPMAP the build's zero-page map.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local cnt, f = {}, 0
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local function zp(x) return mem:read_u8(ZM[x]) end
local FROM = tonumber(os.getenv("FROM") or "3000")
TE1 = mem:install_write_tap(S.S_ERS, S.S_ERS, "ers", function(a, d)
  if f < FROM then return end
  local x = cpu.state["X"].value
  local buf = (mem:read_u8(0xCD) == 0x20) and 1 or 0
  if (x & 1) == 0 then return end
  local k = string.format("4D %02X E5 %02X 2C %02X 44 %02X | %s buf %d DRW %d,%d,%d,%d -> %02X", zp(0x4D), zp(0xE5), zp(0x2C), zp(0x44), (x & 1) == 1 and "enemy " or "player", buf,
    mem:read_u8(S.FT_DRW), mem:read_u8(S.FT_DRW + 1), mem:read_u8(S.FT_DRW + 2), mem:read_u8(S.FT_DRW + 3), d)
  cnt[k] = (cnt[k] or 0) + 1
end)
emu.register_frame_done(function()
  f = f + 1
  if f == tonumber(os.getenv("END")) - 1 then
    local o = io.open("ers.log", "w")
    local ks = {}
    for k in pairs(cnt) do ks[#ks + 1] = k end
    table.sort(ks, function(p, q) return cnt[p] > cnt[q] end)
    for i = 1, math.min(25, #ks) do o:write(string.format("%6d %s\n", cnt[ks[i]], ks[i])) end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
