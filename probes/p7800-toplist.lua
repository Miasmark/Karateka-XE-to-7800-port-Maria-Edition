-- the top rows' piece lists (FINDINGS "The top rows as objects"), both
-- buffers, each frame they changed while playkey.lua's flip count is FROM to
-- TO, to toplist.log: "frame flip buf: piece@x[k0-k1] ...". Runs playkey.lua
-- (its settings: SCENE, INJECT, SNAPK, ...). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM, TO = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("TO") or "99999")
local MAX = tonumber(os.getenv("TOPL_MAX") or "28")
local o = io.open("toplist.log", "w")
local f, last = 0, {"", ""}
emu.register_frame_done(function()
  f = f + 1
  local n = PLAYKEY_N or 0
  if n < FROM or n > TO then return end
  for b = 0, 1 do
    local cnt = mem:read_u8(S.TOPLN + b)
    local t = {}
    for i = 0, cnt - 1 do
      local e = b * MAX + i
      t[#t + 1] = string.format("%d@%d[%d-%d]", mem:read_u8(S.TOPLI + e), mem:read_u8(S.TOPLX + e),
        mem:read_u8(S.TOPLK0 + e), mem:read_u8(S.TOPLK1 + e))
    end
    local s = table.concat(t, " ")
    if s ~= last[b + 1] then
      o:write(string.format("%d %d %s: %s\n", f, n, b == 0 and "A" or "B", s))
      last[b + 1] = s
    end
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
