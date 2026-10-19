-- the largest value of each XEGS zero-page byte in ZPS (hex list), through
-- the build's map (ZPMAP), per scene ($D0) and overall, and the frame it was
-- first reached; to zpmax.log
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local END = tonumber(os.getenv("END") or "20000")
local map = {}
for l in io.lines(os.getenv("ZPMAP")) do local x, a = l:match("(%x+) (%x+)"); if x then map[tonumber(x, 16)] = tonumber(a, 16) end end
local zs = {}
for h in (os.getenv("ZPS") or ""):gmatch("%x+") do zs[#zs + 1] = tonumber(h, 16) end
local best, f = {}, 0
emu.register_frame_done(function()
  f = f + 1
  local sc = mem:read_u8(map[0xD0])
  for _, z in ipairs(zs) do
    local v = mem:read_u8(map[z])
    local k = sc * 256 + z
    if not best[k] or v > best[k][1] then best[k] = {v, f} end
  end
  if f >= END then
    local o = io.open("zpmax.log", "w")
    local ks = {}
    for k in pairs(best) do ks[#ks + 1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do o:write(string.format("scene %d $%02X max %d at frame %d\n", k >> 8, k & 0xFF, best[k][1], best[k][2])) end
    o:close(); M:exit()
  end
end)
