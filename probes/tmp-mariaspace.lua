-- (debug) MARIA's own space: reads by region ($0000-$17FF, $1800-$27FF,
-- $4000-$7FFF, $8000-$BFFF, $C000-$FFFF) in the CPU's program space and in
-- MARIA's "dma" space over frames FROM to FROM+100, to mariaspace.log. Runs playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local ms = M.devices[":maria"].spaces["dma"]
local FROM = tonumber(os.getenv("FROM") or "2000")
local f = 0
local function reg(a) return a < 0x1800 and "0000" or a < 0x2800 and "1800" or a < 0x4000 and "2800" or a < 0x8000 and "4000" or a < 0xC000 and "8000" or "C000" end
local c = {}
local function tap(name) return function(a, d) if f >= FROM and f < FROM + 100 then local k = name .. " " .. reg(a); c[k] = (c[k] or 0) + 1 end end end
TA = mem:install_read_tap(0x0000, 0xFFFF, "msa", tap("cpu"))
TB = ms:install_read_tap(0x0000, 0xFFFF, "msb", tap("maria"))
emu.register_frame_done(function()
  f = f + 1
  if f == FROM + 100 then
    local o = io.open("mariaspace.log", "w")
    local ks = {}
    for k in pairs(c) do ks[#ks + 1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do o:write(k .. " " .. c[k] .. "\n") end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
