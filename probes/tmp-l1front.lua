-- (debug) a companion of p7800-stateplay.lua (SPALSO): in flips PFROM to
-- PTO, each tiles-set blit (L1Blit) and column (L1Col) with its image (the
-- game's $03/$04), its row ($06 - 35), column ($05) and FT_SEEN (non-zero:
-- drawn after the picture's fighters), counted per image, row and seen, to
-- l1front.log at PTO; MAME exits
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
if not SYM_ADDR then dofile(os.getenv("PROBES") .. "/p7800-sym.lua") end
local S = SYM_ADDR
local FR = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local function zp(x) return mem:read_u8(ZM[x]) end
local cnt = {}
local function on() local n = _G.STATEPLAY_N or 0; return n >= FR and n <= TO end
local pend = {}
local function log(kind)
  local src = zp(0x03) + 256 * zp(0x04)
  pend[#pend + 1] = {string.format("%s %04X row %d seen %d", kind, src, (zp(0x06) - 35) & 0xFF,
    mem:read_u8(S.FT_SEEN) ~= 0 and 1 or 0), mem:read_u8(S.FT_SEEN)}
end
-- at the picture's end (TopFlip): a draw made before any fighter (seen 0)
-- is "then fighters" if FT_SEEN is set by then, else "no fighters"
LF_FLIP = mem:install_read_tap(S.TopFlip, S.TopFlip, "lfflip", function(ad, d)
  if ad == cpu.state["PC"].value and on() then
    local after = mem:read_u8(S.FT_SEEN) ~= 0
    for _, e in ipairs(pend) do
      local k = e[1] .. ((e[2] == 0) and (after and " then fighters" or " no fighters") or "")
      cnt[k] = (cnt[k] or 0) + 1
    end
  end
  pend = {}
  return d
end)
LF_TAPS = {}
for _, nm in ipairs({"L1Blit", "L1Col"}) do
  local a = S[nm]
  LF_TAPS[#LF_TAPS + 1] = mem:install_read_tap(a, a, "lf" .. nm, function(ad, d)
    if on() and ad == cpu.state["PC"].value then log(nm == "L1Blit" and "B" or "L") end
    return d
  end)
end
emu.register_frame_done(function()
  if (_G.STATEPLAY_N or 0) > TO then
    local t = {}
    for k, v in pairs(cnt) do t[#t + 1] = string.format("%6d %s", v, k) end
    table.sort(t, function(a, b) return a:sub(8) < b:sub(8) end)
    local o = io.open("l1front.log", "w")
    o:write(table.concat(t, "\n") .. "\n")
    o:close()
    M:exit()
  end
end)
