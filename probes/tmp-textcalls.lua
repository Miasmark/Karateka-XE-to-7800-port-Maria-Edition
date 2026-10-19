-- (debug) each call of the game's text routine $0780: the caller (the
-- stack's return), A X Y, $03-$10, to textcalls.log. Runs playkey.lua.
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local o = io.open("textcalls.log", "w")
local n = 0
TTX = mem:install_read_tap(0xE131, 0xE131, "txt", function(a, d)
  if a ~= cpu.state["PC"].value or n > 200 then return end
  n = n + 1
  local sp = cpu.state["SP"].value & 0xFF
  local ret = mem:read_u8(0x101 + sp) + 256 * mem:read_u8(0x102 + sp) + 1
  local ret2 = mem:read_u8(0x103 + sp) + 256 * mem:read_u8(0x104 + sp) + 1
  local z = {}
  for i = 3, 0x10 do z[#z + 1] = string.format("%02X", mem:read_u8(i)) end
  o:write(string.format("flip %d from %04X (%04X) A %02X X %02X Y %02X zp03-10 %s\n", PLAYKEY_N or -1, ret, ret2,
    cpu.state["A"].value, cpu.state["X"].value, cpu.state["Y"].value, table.concat(z, " ")))
  o:flush()
end)
