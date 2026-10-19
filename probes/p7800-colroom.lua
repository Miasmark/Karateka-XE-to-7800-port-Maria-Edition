-- the slice pages' columns (FINDINGS "Akuma as objects"): each slice left
-- out for want of columns (FtObjNR, bank 5) with its frame, buffer and part
-- (FP_CLS), and the columns both buffers' shown parts took (FT_USE) at
-- each emit's end: to colroom.log, a line a frame with any, and the most
-- at the end. NOPLAY=1 for a recording played back (else playkey.lua).
-- END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local function b(a) return mem:read_u8(a) end
local o = io.open("colroom.log", "w")
local f, nr, most, per = 0, 0, 0, {}
T1 = mem:install_read_tap(S.FtObjNR, S.FtObjNR, "cr1", function(a, d)
  if a == cpu.state["PC"].value and b(S.S_BANK) == 5 then
    nr = nr + 1
    local k = string.format("buf %d part %d", b(S.S_FBUF), b(S.FP_CLS))
    per[k] = (per[k] or 0) + 1
  end
  return d end)
T2 = mem:install_read_tap(S.FtEmitR, S.FtEmitR, "cr2", function(a, d)
  if a == cpu.state["PC"].value and b(S.S_BANK) == 5 then
    local u = b(S.FT_USE) + b(S.FT_USE + 1)
    if u > most then most = u end
  end
  return d end)
local lastnr = 0
emu.register_frame_done(function()
  f = f + 1
  if nr ~= lastnr then
    local t = {}
    for k, v in pairs(per) do t[#t + 1] = k .. " x" .. v end
    o:write(string.format("frame %d: %d slices left out (%s); in use A %d B %d\n", f, nr - lastnr,
      table.concat(t, ", "), b(S.FT_USE), b(S.FT_USE + 1)))
    per = {}
    lastnr = nr
  end
  if f == END - 1 then
    o:write(string.format("slices left out %d, most columns both buffers %d of %d\n", nr, most, S.FT_COLS))
    o:close()
    if os.getenv("NOPLAY") then M:exit() end
  end
end)
if not os.getenv("NOPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
