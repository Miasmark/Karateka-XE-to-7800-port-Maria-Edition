-- (debug) each frame PFROM-PTO: both buffers' level-1 instances (L1_N, the
-- shapes and x: L1_SHA/L1_XA, L1_SHB/L1_XB), their views (L1_V) and the game's
-- $52/$50, when anything changes, to l1inst.log; MAME exits after PTO
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FR = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local N = 24
local o = io.open("l1inst.log", "w")
local f, last = 0, ""
local function r(a) return mem:read_u8(a) end
emu.register_frame_done(function()
  f = f + 1
  if f >= FR and f <= TO then
    local t = {string.format("$52 %02X $50 %02X", r(S.G_Z52), r(S.G_Z50))}
    for b = 0, 1 do
      local sh, x = (b == 0) and S.L1_SHA or S.L1_SHB, (b == 0) and S.L1_XA or S.L1_XB
      local n = r(S.L1_N + b)
      local l = {}
      for i = 0, n - 1 do l[#l + 1] = string.format("%d@%d", r(sh + i), r(x + i)) end
      t[#t + 1] = string.format("%s V%02X%02X n%d [%s]", b == 0 and "A" or "B", r(S.L1_V + 2 * b + 1), r(S.L1_V + 2 * b), n, table.concat(l, " "))
    end
    local s = table.concat(t, " | ")
    if s ~= last then o:write("f" .. f .. " " .. s .. "\n"); last = s end
  end
  if f > TO then o:close(); M:exit() end
end)
