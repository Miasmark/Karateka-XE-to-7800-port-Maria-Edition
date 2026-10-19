-- the band zones' lists in use (FINDINGS "The fighters as objects: step 1,
-- the band's lists"): each frame, the DLL MARIA is given (the last DPPH/DPPL
-- writes: DLL_A or DLL_B) walked to DLL_LINES lines, and its zones whose
-- display list is in the band area (BAND_A-BAND_BEND) counted, by mode: the
-- title up (S_TITLEA/B), the story up (S_STORY), else play. Each band list
-- must be the bitmap row's two objects and the end (as written: a canvas or
-- glyph written over it would show). To bandlists.log at the end: per mode
-- and buffer, frames seen, the most band zones, the highest list end; any
-- list outside its buffer's half (A BAND_A-BAND_AEND, B BAND_B-BAND_BEND)
-- or not as written.
-- Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local LINES = 243
local f = 0
local stat = {}
local bad = {}
local dpph, dppl = 0, 0
TD = mem:install_write_tap(0x2C, 0x2C, "bdh", function(a, d) dpph = d end)
TL = mem:install_write_tap(0x30, 0x30, "bdl", function(a, d) dppl = d end)
local function intact(a)
  local b = {}
  for i = 0, 9 do b[i] = mem:read_u8(a + i) end
  return b[1] == b[5] and b[1] ~= 0 and b[2] == b[6] and b[3] == 0 and b[7] == 80
    and b[4] == (b[0] + 20) & 0xFF and b[9] == 0
end
local function walk(dll, lo, hi, key)
  local lines, n, top = 0, 0, 0
  for e = 0, 84 do
    local b0 = mem:read_u8(dll + 3 * e)
    local a = mem:read_u8(dll + 3 * e + 1) * 256 + mem:read_u8(dll + 3 * e + 2)
    if a >= S.BAND_A and a < S.BAND_BEND then
      n = n + 1
      -- the list's end: its objects' headers to the end marker
      local p = a
      while mem:read_u8(p + 1) ~= 0 do
        p = p + ((mem:read_u8(p + 1) & 0x1F) == 0 and 5 or 4)
      end
      if p + 2 > top then top = p + 2 end
      if not intact(a) then bad[#bad + 1] = string.format("%d %s $%04X not as written", f, key, a) end
      if a < lo or p + 2 > hi then bad[#bad + 1] = string.format("%d %s $%04X-$%04X", f, key, a, p + 1) end
    end
    lines = lines + (b0 & 0x0F) + 1
    if lines >= LINES then break end
  end
  local s = stat[key] or { frames = 0, most = 0, top = 0 }
  s.frames = s.frames + 1
  if n > s.most then s.most = n end
  if top > s.top then s.top = top end
  stat[key] = s
end
emu.register_frame_done(function()
  f = f + 1
  local mode = (mem:read_u8(S.S_TITLEA) | mem:read_u8(S.S_TITLEB)) ~= 0 and "title"
    or mem:read_u8(S.S_STORY) ~= 0 and "story" or "play"
  local dll = dpph * 256 + dppl
  if f > 60 and dll == S.DLL_A then walk(S.DLL_A, S.BAND_A, S.BAND_AEND, mode .. " A")
  elseif f > 60 and dll == S.DLL_B then walk(S.DLL_B, S.BAND_B, S.BAND_BEND, mode .. " B") end
  if f == END - 1 then
    local o = io.open("bandlists.log", "w")
    local keys = {}
    for k in pairs(stat) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local s = stat[k]
      o:write(string.format("%-8s frames %6d  band zones at most %2d  lists end by $%04X\n", k, s.frames, s.most, s.top))
    end
    o:write(string.format("outside their half or not as written: %d\n", #bad))
    for i = 1, math.min(#bad, 20) do o:write(bad[i] .. "\n") end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
