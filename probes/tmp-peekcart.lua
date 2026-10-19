-- (debug) cart RAM bytes as Lua reads them at frames AT (comma list): $6300-$630F,
-- $6010-$601F and $7C40-$7C4F, with $D0 and S_SCENEBANK, to peekcart.log. Runs playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local at = {}
for t in (os.getenv("AT") or ""):gmatch("%d+") do at[tonumber(t)] = true end
local f = 0
local o = io.open("peekcart.log", "w")
emu.register_frame_done(function()
  f = f + 1
  if at[f] then
    local function row(a) local t = {} for k = 0, 15 do t[#t + 1] = string.format("%02X", mem:read_u8(a + k)) end return table.concat(t, " ") end
    o:write(string.format("f%d D0=%02X bank=%02X\n  6300: %s\n  6010: %s\n  7C40: %s\n", f, mem:read_u8(0xD0),
      mem:read_u8(S.S_SCENEBANK), row(0x6300), row(0x6010), row(0x7C40)))
    o:flush()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
