-- the RAM census (FINDINGS "The RAM census"): every address of console RAM
-- ($1800-$27FF) and cartridge RAM ($4000-$7FFF) written after the boot's
-- clear (ClrRam-ClrCart's loop: before it, the BIOS's writes) is marked; with
-- READS=lo-hi,... (hex ranges) also every read there after the clear (by
-- anything but an instruction fetch). To ramcensus.log every 200 frames
-- and at END (the scripted player or a recording may end the run first):
-- "W" then 64 hex digits a line (a bit an address, 256 addresses a line),
-- "R" the same for reads. WITHPLAY=1: playkey.lua drives. ALSO: another
-- probe run alongside (e.g. p7800-jumpto.lua, to reach the ending).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local c0, c1 = SYM_ADDR.ClrRam, SYM_ADDR.ClrCart + 16
local END = tonumber(os.getenv("END") or "300")
local W, R = {}, {}
local booted, f = false, 0
local function pc() return cpu.state["PC"].value end
CT = {}
for _, r in ipairs({{0x1800, 0x27FF}, {0x4000, 0x7FFF}}) do
  CT[#CT + 1] = mem:install_write_tap(r[1], r[2], "cw" .. r[1], function(a, d)
    local p = pc()
    if p >= c0 and p < c1 then booted = true
    elseif booted then W[a] = true end
    return d end)
end
for lo, hi in (os.getenv("READS") or ""):gmatch("(%x+)-(%x+)") do
  CT[#CT + 1] = mem:install_read_tap(tonumber(lo, 16), tonumber(hi, 16), "cr" .. lo, function(a, d)
    local p = pc()
    if booted and a ~= p and not (p >= c0 and p < c1) then R[a] = true end   -- (the clear's own
    -- STA abs,X: the 6502's dummy read of the target, which MAME makes too)
    return d end)
end
local function dump()
  local o = io.open("ramcensus.log", "w")
  for _, set in ipairs({{"W", W}, {"R", R}}) do
    for page = 0x18, 0x7F do
      if page < 0x28 or page >= 0x40 then
        local t = {}
        for i = 0, 255, 4 do
          local v = 0
          for k = 0, 3 do if set[2][page * 256 + i + k] then v = v + (8 >> k) end end
          t[#t + 1] = string.format("%X", v)
        end
        o:write(string.format("%s %02X %s\n", set[1], page, table.concat(t)))
      end
    end
  end
  o:write(string.format("frame %d\n", f))
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if f % 200 == 0 then dump() end
  if f >= END then dump(); M:exit() end
end)
if os.getenv("ALSO") then dofile(os.getenv("PROBES") .. "/" .. os.getenv("ALSO"))   -- (another probe: its
elseif os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end        -- WITHPLAY then its own)
