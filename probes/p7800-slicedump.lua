-- the slice pages ($73-$7A) as MARIA reads them (FINDINGS "The fighters as
-- objects: speed"): at the end of the first frame after flip AT's display
-- list change (as playkey.lua's SNAPDL), all 8 pages to slices.bin (page $73
-- first), with the frame's DLL and the records to slicedump.log. Runs
-- playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local AT = tonumber(os.getenv("AT") or "1280")
-- FRAME: from this frame instead (a recording played back: no playkey);
-- also each buffer's front boxes and Akuma's captured blits then
local FRAME = tonumber(os.getenv("FRAME") or "")
local fr
local function b(a) return mem:read_u8(a) end
local dpp, at, wait, due, done = {[0x2C] = 0, [0x30] = 0}, nil, false, false, false
local delay   -- (alongside p7800-stateplay.lua: two frames after its flip)
TWSD = mem:install_write_tap(0x2C, 0x30, "sd", function(a, d)
  if a ~= 0x2C and a ~= 0x30 then return end
  dpp[a] = d
  if wait and dpp[0x2C] * 256 + dpp[0x30] ~= at then wait = false; due = true end
end)
SDFD = emu.register_frame_done(function()
  if done then return end
  fr = (fr or 0) + 1
  local hit = FRAME and fr == FRAME or (not FRAME and (PLAYKEY_N or STATEPLAY_N or 0) == AT)
  if not wait and not due and not delay and hit then
    if STATEPLAY_N then delay = 2 else wait = true; at = dpp[0x2C] * 256 + dpp[0x30] end
  end
  if delay then delay = delay - 1; if delay == 0 then delay = nil; due = true end end
  if due then
    done = true
    if FRAME or os.getenv("NOPLAY") then M.video:snapshot() end
    local f = io.open("slices.bin", "wb")
    for p = 0x73, 0x7A do
      local t = {}
      for i = 0, 255 do t[#t + 1] = string.char(b(p * 256 + i)) end
      f:write(table.concat(t))
    end
    f:close()
    local o = io.open("slicedump.log", "w")
    o:write(string.format("flip %d frame %d DLL $%02X%02X\n", PLAYKEY_N or -1, fr, dpp[0x2C], dpp[0x30]))
    for x = 0, 3 do
      o:write(string.format("record %d: V %d $20 %d $21 %d $22 %d $50 %d $3E %d $36 %d\n", x, b(S.FR_V + x),
        b(S.FR_20 + x), b(S.FR_21 + x), b(S.FR_22 + x), b(S.FR_50 + x), b(S.FR_3E + x), b(S.FR_36 + x)))
    end
    for buf = 0, 1 do
      o:write(string.format("buffer %d: boxes shown %d, recorded %d, seen %d; Akuma V %d N %d\n", buf,
        b(S.FG_NS + buf), b(S.FGR_N + buf), b(S.FT_SEEN + buf), b(S.AK_V + buf), b(S.AK_N + buf)))
      for i = 0, b(S.FG_NS + buf) - 1 do
        local k = 8 * buf + i
        o:write(string.format("  box cols %d+%d rows %d-%d\n", b(S.FG_C0 + k), b(S.FG_W + k), b(S.FG_R0 + k), b(S.FG_R1 + k)))
      end
      for i = 0, b(S.AK_N + buf) - 1 do
        local k = S.AK_MAX * buf + i
        o:write(string.format("  blit %02X%02X bank %d col %d row %d shift %d flags %02X\n", b(S.AK_HI + k), b(S.AK_LO + k),
          b(S.AK_BK + k), b(S.AK_COL + k), b(S.AK_ROW + k), b(S.AK_SH + k), b(S.AK_FL + k)))
      end
    end
    local dll = dpp[0x2C] * 256 + dpp[0x30]
    local line = 0
    for e = 0, 84 do
      local b0 = b(dll + 3 * e)
      local a = b(dll + 3 * e + 1) * 256 + b(dll + 3 * e + 2)
      local h = (b0 & 0x0F) + 1
      if line >= 120 and line < 200 then
        local objs, q = {}, a
        while b(q + 1) ~= 0 and #objs < 20 do
          objs[#objs + 1] = string.format("$%02X%02X p%d w%d x%d", b(q + 2), b(q), b(q + 1) >> 5, (-(b(q + 1)) & 0x1F), b(q + 3))
          q = q + 4
        end
        o:write(string.format("  line %3d +%d list $%04X: %s\n", line, h, a, table.concat(objs, ", ")))
      end
      line = line + h
      if line >= 243 then break end
    end
    o:close()
    if FRAME or os.getenv("NOPLAY") then M:exit() end
  end
end)
-- (NOPLAY=1: alongside p7800-stateplay.lua, its flips: STATEPLAY_N)
if not FRAME and not os.getenv("NOPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
