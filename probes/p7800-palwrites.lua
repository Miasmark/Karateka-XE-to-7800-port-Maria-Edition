-- the palette registers' writes ($20-$3F): from frame FROM to TO, each
-- register's values written with the scan lines they were written on (a
-- DLI's mid-screen rewrite shows as a second line), to palwrites.log at TO.
-- Also each register's last write. Alongside p7800-stateplay.lua (SPALSO) or playkey.lua's runs.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
-- the scan line, estimated as p7800-colwrites.lua does (this MAME's screen
-- has no vpos)
local t0 = 0
local function line() return math.floor((M.time:as_double() - t0) * 59.92 * 263) end
local FROM = tonumber(os.getenv("FROM") or "0")
local TO = tonumber(os.getenv("TO") or "1000")
local f, seen, last = 0, {}, {}
local function pw(a, d)
  if f < FROM or f > TO or (a & 3) == 0 then return end
  local k = string.format("$%02X = %02X line %3d", a, d, line())
  seen[k] = (seen[k] or 0) + 1
  last[a] = string.format("$%02X = %02X frame %d line %d", a, d, f, line())
end
TWPW = mem:install_write_tap(0x21, 0x3F, "pw", pw)
PWFD = emu.register_frame_done(function()
  t0 = M.time:as_double()
  f = f + 1
  if f == TO then
    local o = io.open("palwrites.log", "w")
    local ks = {}
    for k in pairs(seen) do ks[#ks + 1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do o:write(string.format("%6d %s\n", seen[k], k)) end
    o:write("last:\n")
    for r = 0x21, 0x3F do if last[r] then o:write(last[r] .. "\n") end end
    o:close()
    M:exit()
  end
end)
