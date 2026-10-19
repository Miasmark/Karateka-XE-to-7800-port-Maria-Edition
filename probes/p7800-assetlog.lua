-- every distinct image the port's blitter draws (the header read's RTS, XEGS
-- $29FA = engine2 $79FA here; the source through the zero-page map, XEGS
-- $03/$04 less 2, rows $0D, width $0E), frames FROM-END: "frame src rows
-- width hex" the first time each (src, bytes) is seen, and a snapshot then
-- if SNAP=1; to assetlog.log. For matching against the original's inventory
-- (probes/assetinv.py) when a 7800 recording reaches what the XEGS runs
-- didn't.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "20000")
local AT = tonumber(os.getenv("AT") or "79FA", 16)
local ZP = {}
for l in io.lines(os.getenv("ZPMAP")) do
  local x, a = l:match("(%x+) (%x+)")
  if x then ZP[tonumber(x, 16)] = tonumber(a, 16) end
end
local function z(n) return mem:read_u8(ZP[n]) end
local f, seen, busy = 0, {}, false
local o = io.open("assetlog.log", "w")
T = mem:install_read_tap(AT, AT, "as78", function(a, d)
  if busy or f < FROM or PCs.value ~= AT then return d end
  busy = true
  local src = (z(0x03) + 256 * z(0x04) - 2) & 0xFFFF
  local rows, width = z(0x0D), z(0x0E)
  local t = {}
  for i = 0, 1 + rows * width do t[#t + 1] = string.format("%02X", mem:read_u8((src + i) & 0xFFFF)) end
  local h = table.concat(t)
  local key = src .. h
  if not seen[key] then
    seen[key] = true
    o:write(string.format("%d %04X %d %d %s\n", f, src, rows, width, h)); o:flush()
  end
  busy = false
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then o:close(); M:exit() end
end)
