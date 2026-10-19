-- pages $40-$4E (the top data) with S_TSET and $D0 at the frame ends of flips K (comma list), to topdump.txt
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local K = {}
for v in (os.getenv("K") or "300"):gmatch("%d+") do K[tonumber(v)] = true end
local o = io.open("topdump.txt", "w")
local last = -1
emu.register_frame_done(function()
  local n = PLAYKEY_N or 0
  if n ~= last and K[n] then
    local h = {}
    for p = 0x40, 0x4E do
      local s = {}
      for b = 0, 255 do s[#s + 1] = string.format("%02X", mem:read_u8(p * 256 + b)) end
      h[#h + 1] = table.concat(s)
    end
    o:write(string.format("flip %d D0 %d set %d %s\n", n, mem:read_u8(ZM[0xD0]), mem:read_u8(S.S_TSET), table.concat(h, " ")))
    o:flush()
  end
  last = n
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
