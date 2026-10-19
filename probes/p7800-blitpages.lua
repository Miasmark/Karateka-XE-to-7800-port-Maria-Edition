-- the pages $A0-$BF each scene's blits read their images from (the blitter
-- entries A $784E, AR $79C2, M $7B82, MR $7B8B; the image from $03/$04, its
-- extent from its header, read with the scene page in), by the scene loaded
-- ($D0), to blitpages.log at the end: "scene page count". Runs playkey.lua
-- (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local END = tonumber(os.getenv("END") or "6000")
local ZP = {}
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZP[tonumber(z, 16)] = tonumber(t, 16) end
end
local function z(n) return mem:read_u8(ZP[n]) end
local seen, f = {}, 0
TAPS = {}
for _, a in ipairs({0x784E, 0x79C2, 0x7B82, 0x7B8B}) do
  TAPS[#TAPS + 1] = mem:install_read_tap(a, a, "bp" .. a, function(ad, d)
    if ad ~= PCs.value then return d end
    local src = z(0x04) * 256 + z(0x03)
    if src >= 0xA000 and src < 0xC000 then
      local last = src + 1 + mem:read_u8(src) * mem:read_u8(src + 1)
      local sc = z(0xD0)
      for p = src >> 8, math.min(last, 0xBFFF) >> 8 do
        local k = sc * 256 + p
        seen[k] = (seen[k] or 0) + 1
      end
    end
    return d end)
end
emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    local o = io.open("blitpages.log", "w")
    local ks = {}
    for k in pairs(seen) do ks[#ks + 1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do o:write(string.format("%d %02X %d\n", k >> 8, k & 0xFF, seen[k])) end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
