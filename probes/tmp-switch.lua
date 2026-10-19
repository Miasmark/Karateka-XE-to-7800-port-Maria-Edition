-- (debug) the cutscene switch frames: each frame, the game's colour scheme
-- (G_L0F0C), the held list (HOLD_N, V2), the list asked for (S_DLIST) and
-- how many of the game's DLIs (NmiDliRun) and vertical blanks (NmiVbiRun)
-- ran; a line when any of them changes, to switch.log; snapshots at SNAPS
-- (frames), or AUTOSNAP frames from each scheme change; MAME exits at END. SYM: the build's symbol file.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "20000")
local snaps = {}
for t in (os.getenv("SNAPS") or ""):gmatch("%d+") do snaps[tonumber(t)] = true end
local o = io.open("switch.log", "w")
local f, dli, vbi, last = 0, 0, 0, ""
local AUTO = tonumber(os.getenv("AUTOSNAP") or "0")   -- (AUTOSNAP=n: snapshots of the n frames from each scheme change)
local lastsch, pend = -1, 0
SW_TAPS = {}
local function at(name, fn)
  local a = S[name]
  if not a then return end
  SW_TAPS[#SW_TAPS + 1] = mem:install_read_tap(a, a, "sw" .. name, function(ad, d)
    if ad == cpu.state["PC"].value then fn() end
    return d
  end)
end
at("NmiDliRun", function() dli = dli + 1 end)
at("NmiVbiRun", function() vbi = vbi + 1 end)
local dpph, dppl = 0, 0      -- (the list MARIA was last given: DPPH/DPPL writes)
SW_DPP = mem:install_write_tap(0x2C, 0x30, "swdpp", function(a, d)
  if a == 0x2C then dpph = d elseif a == 0x30 then dppl = d end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  local hold = S.HOLD_N and mem:read_u8(S.HOLD_N) or -1
  local s = string.format("sch %d hold %d list $%02X%02X dli %d vbi %d dll $%02X%02X", mem:read_u8(S.G_L0F0C), hold,
    mem:read_u8(S.S_DLIST + 1), mem:read_u8(S.S_DLIST), dli, vbi, dpph, dppl)
  if s ~= last then o:write(string.format("f%d %s\n", f, s)); last = s end
  dli, vbi = 0, 0
  local sch = mem:read_u8(S.G_L0F0C)
  if AUTO > 0 and f > 300 and sch ~= lastsch and lastsch >= 0 then pend = AUTO; o:write(string.format("-- snap from f%d\n", f)) end
  lastsch = sch
  if snaps[f] or pend > 0 then M.video:snapshot(); if pend > 0 then pend = pend - 1 end end
  if f >= END then o:close(); M:exit() end
end)
