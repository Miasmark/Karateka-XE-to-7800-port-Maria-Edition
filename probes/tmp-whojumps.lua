-- (debug) playkey.lua, plus: the first time the CPU fetches an opcode in
-- LO-HI (default cart RAM, $4000-$7FFF), the stack's top 16 bytes, the
-- registers and the last 64 distinct opcode fetches before it seen in ROM
-- (a ring of the read tap's PC samples over $8000-$FFFF), to whojumps.log
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local LO = tonumber(os.getenv("LO") or "4000", 16)
local HI = tonumber(os.getenv("HI") or "7FFF", 16)
local ring, rn, last = {}, 0, -1
local done, busy = false, false
TWJ1 = mem:install_read_tap(0x8000, 0xFFFF, "wjrom", function(a, d)
  if done or busy then return d end
  busy = true
  local pc = cpu.state["PC"].value
  if pc == a and pc ~= last then
    rn = rn % 64 + 1
    ring[rn] = pc
    last = pc
  end
  busy = false
  return d
end)
TWJ2 = mem:install_read_tap(LO, HI, "wjram", function(a, d)
  if done or busy then return d end
  busy = true
  local pc = cpu.state["PC"].value
  if pc == a then
    done = true
    local o = io.open("whojumps.log", "w")
    local sp = cpu.state["SP"].value & 0xFF
    o:write(string.format("opcode fetch at $%04X; A %02X X %02X Y %02X SP %02X\nstack:", a,
      cpu.state["A"].value & 0xFF, cpu.state["X"].value & 0xFF, cpu.state["Y"].value & 0xFF, sp))
    for k = 1, 16 do o:write(string.format(" %02X", mem:read_u8(0x100 + ((sp + k) & 0xFF)))) end
    o:write("\nlast ROM fetches (oldest first):")
    for k = 1, 64 do
      local v = ring[(rn + k - 1) % 64 + 1]
      if v then o:write(string.format(" %04X", v)) end
    end
    o:write("\n")
    o:close()
  end
  busy = false
  return d
end)
