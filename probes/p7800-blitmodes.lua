-- every distinct (image, mode, blitter entry) the port draws from frame FROM
-- to END, with the scene ($D0), the first frame and the count, to
-- blitmodes.log at the end: "scene entry src mode count first rows width
-- top". Mode as the game's $0F: 0 OR (a sprite), negative AND (a mask),
-- else store. For a cartridge of the engine-at-$7300 layout (the entries
-- at $784E A, $79C2 AR, $7B82 M, $7B8B MR) unless E2 (hex) gives the
-- blitter module's base ($7800 there). Zero page from ZPMAP. Pairs with a
-- recording: EXTRA="-input_directory ... -playback NAME.inp".
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "20000")
local base = tonumber(os.getenv("E2") or "7800", 16) - 0x2800
local ZP = {}
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZP[tonumber(z, 16)] = tonumber(t, 16) end
end
local function z(n) return mem:read_u8(ZP[n]) end
local seen, order, f = {}, {}, 0
TAPS = {}
for xa, k in pairs({[0x284E] = "A", [0x29C2] = "AR", [0x2B82] = "M", [0x2B8B] = "MR"}) do
  TAPS[#TAPS + 1] = mem:install_read_tap(base + xa, base + xa, "bm" .. k, function(a, d)
    if f < FROM or a ~= PCs.value then return d end
    local src = z(0x04) * 256 + z(0x03)
    local mode = z(0x0F)
    local key = string.format("%d %s %04X %02X", z(0xD0), k, src, mode)
    if not seen[key] then
      seen[key] = {0, f, mem:read_u8(src), mem:read_u8(src + 1), z(0x06)}
      order[#order + 1] = key
    end
    seen[key][1] = seen[key][1] + 1
    return d end)
end
emu.register_frame_done(function()
  f = f + 1
  if f >= END then
    local o = io.open("blitmodes.log", "w")
    for _, k in ipairs(order) do
      local s = seen[k]
      o:write(string.format("%s %d %d %d %d %d\n", k, s[1], s[2], s[3], s[4], s[5]))
    end
    o:close()
    M:exit()
  end
end)
