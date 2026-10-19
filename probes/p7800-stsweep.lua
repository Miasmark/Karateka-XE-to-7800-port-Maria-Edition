-- the status bar as objects against every arrow count: runs the scripted
-- player (playkey.lua, with its settings: give it a large KEYN and END) and,
-- from flip SW0 (default 250) once the foe has health, holds the player's
-- and the foe's health ($B6, $B7) at each pair below for 40 frames. Every
-- frame it logs, for both buffers, the arrows set (S_STP/S_STF) and the
-- status rows as MARIA shows them (the buffer's list drawn on blank), with
-- the health and $07; and each call of the sound starter with the warning
-- tune ($15). To stsweep.log; the check is probes/stsweep.py
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local Z = {}
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then Z[tonumber(z, 16)] = tonumber(t, 16) end
end
local PAIRS = {}
for k = 1, 27 do PAIRS[#PAIRS + 1] = {k, 28 - k} end
for _, p in ipairs({{1, 1}, {2, 2}, {3, 3}, {1, 2}, {2, 1}, {4, 4}, {24, 1}, {1, 24}, {25, 3}, {3, 25}}) do
  PAIRS[#PAIRS + 1] = p
end
local SW0 = tonumber(os.getenv("SW0") or "250")
local HOLD = 40
local TAIL = tonumber(os.getenv("TAIL") or "0")
-- SNAPW: frames from the sweep's start (comma list) to take a screenshot at
local SNAPF = {}
for k in (os.getenv("SNAPW") or ""):gmatch("%d+") do SNAPF[tonumber(k)] = true end
local log = io.open("stsweep.log", "w")
local DL = {SYM_ADDR.STATUS_DLA, SYM_ADDR.STATUS_DLB}
local SP, SF = SYM_ADDR.S_STP, SYM_ADDR.S_STF
local frame, start = 0, nil

local function shown(dl)       -- the list's objects on blank: 7 rows of 40 bytes, hex
  local px = {}
  for r = 0, 6 do px[r] = {} for x = 0, 159 do px[r][x] = 0 end end
  local n = 0
  while mem:read_u8(dl + 1) ~= 0 and n < 20 do
    local lo, pw, hi, hp = mem:read_u8(dl), mem:read_u8(dl + 1), mem:read_u8(dl + 2), mem:read_u8(dl + 3)
    local w = (32 - (pw & 31)) & 31
    for r = 0, 6 do
      local at = (hi + 6 - r) * 256 + lo
      for j = 0, w - 1 do
        local v = mem:read_u8(at + j)
        for k = 0, 3 do
          local p = (v >> (6 - 2 * k)) & 3
          local x = (hp + 4 * j + k) & 0xFF
          if p ~= 0 and x < 160 then px[r][x] = p end
        end
      end
    end
    dl = dl + 4
    n = n + 1
  end
  local t = {}
  for r = 0, 6 do
    for i = 0, 39 do
      local v = 0
      for k = 0, 3 do v = v | (px[r][4 * i + k] << (6 - 2 * k)) end
      t[#t + 1] = string.format("%02X", v)
    end
  end
  return table.concat(t), n
end

TUNE = mem:install_read_tap(SYM_ADDR.G_L2422, SYM_ADDR.G_L2422, "tune", function(a, d)
  if a == cpu.state["PC"].value and (cpu.state["A"].value & 0xFF) == 0x15 then
    log:write(string.format("tune f%d\n", frame))
  end
  return d end)

emu.register_frame_done(function()
  frame = frame + 1
  if not start then
    if (PLAYKEY_N or 0) >= SW0 and mem:read_u8(Z[0xB7]) > 0 then
      start = frame
      log:write(string.format("start f%d flip %d B6=%d B7=%d\n", frame, PLAYKEY_N, mem:read_u8(Z[0xB6]), mem:read_u8(Z[0xB7])))
    end
    return
  end
  local i = (frame - start) // HOLD + 1
  -- then TAIL frames more (default 0), the health no longer held
  if frame - start >= #PAIRS * HOLD + TAIL then log:write("done\n"); log:close(); M:exit(); return end
  if SNAPF[frame - start] then M.video:snapshot() end
  local w = (frame - start) % HOLD
  local out = {string.format("w%d %d f%d B6=%d B7=%d 07=%02X", i, w, frame,
    mem:read_u8(Z[0xB6]), mem:read_u8(Z[0xB7]), mem:read_u8(Z[0x07]))}
  if i > #PAIRS then out[1] = out[1] .. string.format(" flip=%d", PLAYKEY_N or -1) end
  for b = 1, 2 do
    local rows, n = shown(DL[b])
    out[#out + 1] = string.format("%d %d %d %s", mem:read_u8(SP + b - 1), mem:read_u8(SF + b - 1), n, rows)
  end
  log:write(table.concat(out, " | ") .. "\n")
  -- the next frame's health, held: the game's own writes (hits, a death)
  -- store the held value instead
  HELD = PAIRS[((frame + 1 - start) // HOLD) + 1]
  if HELD then mem:write_u8(Z[0xB6], HELD[1]); mem:write_u8(Z[0xB7], HELD[2]) end
end)
HB6 = mem:install_write_tap(Z[0xB6], Z[0xB6], "hb6", function(a, d) return HELD and HELD[1] or d end)
HB7 = mem:install_write_tap(Z[0xB7], Z[0xB7], "hb7", function(a, d) return HELD and HELD[2] or d end)
