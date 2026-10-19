-- (debug) each entry of FtEmitAk in frames PFROM-PTO: the frame, the buffer
-- (S_FBUF), its doorway masks (FT_ML, FT_MRI), FT_SEEN, and Akuma's blits
-- (AK_N; each one's column AK_COL and flags AK_FL), to akmask.log; MAME exits
-- after PTO. SYM: the build's symbol file.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FR = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local AKMAX = 10
local o = io.open("akmask.log", "w")
local f = 0
local function r(a) return mem:read_u8(a) end
AM_TAP = mem:install_read_tap(S.FtEmitAk, S.FtEmitAk, "akm", function(ad, d)
  if f >= FR and f <= TO and ad == cpu.state["PC"].value then
    local b = r(S.S_FBUF)
    local n = r(S.AK_N + b)
    local t = {}
    for i = 0, n - 1 do
      local k = b * AKMAX + i
      t[#t + 1] = string.format("c%d/%02X", r(S.AK_COL + k), r(S.AK_FL + k))
    end
    o:write(string.format("f%d buf %d ML %d MRI %d seen %d,%d ak %d: %s\n", f, b, r(S.FT_ML + b), r(S.FT_MRI + b),
      r(S.FT_SEEN), r(S.FT_SEEN + 1), n, table.concat(t, " ")))
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f > TO then o:close(); M:exit() end
end)
