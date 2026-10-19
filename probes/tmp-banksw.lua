-- (debug) bank switches: every CPU write to the bank window ($8000-$BFFF),
-- by scene (the game's G_ZD0), phase (L a load under the blank list, T the
-- title's or story's text, P play), the bank selected and the instruction
-- (CURPC); and frames, per scene and phase. To banksw.log at each 1000th
-- frame: "frames scene phase n" and "sw scene phase bank pc count". Runs
-- playkey.lua (not under port/replay.sh).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local st = cpu.state
local reg = {[0x2C] = 0, [0x30] = 0}
local busy, f = false, 0
local cnt, frames = {}, {}
local function ctx()
  local ph = "P"
  if reg[0x2C] * 256 + reg[0x30] == S.BLANK_DLL then ph = "L"
  else
    busy = true
    if mem:read_u8(S.S_STORY) ~= 0 or mem:read_u8(S.S_TITLEA) ~= 0 or mem:read_u8(S.S_TITLEB) ~= 0 then ph = "T" end
    busy = false
  end
  busy = true
  local sc = mem:read_u8(S.G_ZD0)
  busy = false
  return sc, ph
end
TREG = mem:install_write_tap(0x2C, 0x30, "bs_reg", function(a, d) if reg[a] then reg[a] = d end end)
TB = mem:install_write_tap(0x8000, 0xBFFF, "bs_w", function(a, d)
  if busy then return end
  local sc, ph = ctx()
  local pc = st["CURPC"] and st["CURPC"].value or st["PC"].value
  local k = string.format("sw %d %s %02X %04X", sc, ph, d, pc)
  cnt[k] = (cnt[k] or 0) + 1
end)
emu.register_frame_done(function()
  f = f + 1
  local sc, ph = ctx()
  local k = string.format("frames %d %s", sc, ph)
  frames[k] = (frames[k] or 0) + 1
  if f % 1000 == 0 then
    local o = io.open("banksw.log", "w")
    for k2, n in pairs(frames) do o:write(k2 .. " " .. n .. "\n") end
    for k2, n in pairs(cnt) do o:write(k2 .. " " .. n .. "\n") end
    o:close()
  end
end)
if not os.getenv("PLAYBACK") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
