-- the bytes at ADDRS (hex, comma-separated) at the end of frames FRAMES
-- (comma-separated), to peek.log. ALSO: another probe alongside.
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local want, addrs, f = {}, {}, 0
for n in (os.getenv("FRAMES") or ""):gmatch("%d+") do want[tonumber(n)] = true end
for h in (os.getenv("ADDRS") or ""):gmatch("%x+") do addrs[#addrs + 1] = tonumber(h, 16) end
local o = io.open("peek.log", "w")
emu.register_frame_done(function()
  f = f + 1
  if want[f] then
    local t = {}
    for _, a in ipairs(addrs) do t[#t + 1] = string.format("$%04X=%02X", a, mem:read_u8(a)) end
    o:write(f .. " " .. table.concat(t, " ") .. "\n"); o:flush()
  end
end)
if os.getenv("ALSO") then dofile(os.getenv("PROBES") .. "/" .. os.getenv("ALSO")) end
