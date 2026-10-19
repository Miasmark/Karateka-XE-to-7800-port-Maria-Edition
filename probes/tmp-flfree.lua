-- per flip: free codes (FL_HEAD's list), distinct codes in use per buffer, the lowest free count seen
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local o = io.open("flfree.log", "w")
local last = -1
local minfree = 999
emu.register_frame_done(function()
  local n = PLAYKEY_N or 0
  if n == last then return end
  last = n
  if mem:read_u8(S.S_FLLIVE) == 0 then return end
  local free, c, guard = 0, mem:read_u8(S.FL_HEAD), 0
  while c ~= 0 and guard < 200 do free = free + 1; c = mem:read_u8(0x6000 + c + 1); guard = guard + 1 end
  local used = {}
  for b = 0, 1 do for z = 0, 3 do
    local map = (0x58 + 2 * b + z // 2) * 256 + 212 + (z % 2) * 20
    for k = 0, 19 do used[mem:read_u8(map + k)] = true end
  end end
  local nu = 0
  for _ in pairs(used) do nu = nu + 1 end
  if free < minfree then minfree = free end
  o:write(string.format("flip %d free %d distinct %d (free+used %d)\n", n, free, nu, free + nu))
  o:flush()
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
