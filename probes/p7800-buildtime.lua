-- per frame from FROM to END: each list build's start and end (the frame line
-- estimated as in p7800-listlog, and MSTAT's vertical-blank bit at the end),
-- and the game's DLIs dropped because the vertical blank was still running
-- (NmiDliNot with S_INVBI set); to buildtime.log, a summary at its end.
-- WITHPLAY: playkey.lua's input as well.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local t0 = 0
local function vpos() return math.floor((M.time:as_double() - t0) * 59.92 * 263) end
local f = 0
local ev, inbuild, bstart, tstart = {}, false, 0, 0
local nbuild, nlate, ndrop, dropframes, maxend = 0, 0, 0, 0, 0
local dropped = 0
local function pc() return cpu.state["PC"].value end
TB = mem:install_read_tap(S.BuildDll, S.BuildDll, "bt0", function(a, d)
  if a == pc() and f >= FROM then inbuild = true; bstart = vpos(); tstart = M.time:as_double() end
  return d end)
local function done(a, d)
  if a == pc() and inbuild then
    inbuild = false
    local e, vb = vpos(), (mem:read_u8(0x28) & 0x80) ~= 0
    local len = math.floor((M.time:as_double() - tstart) * 59.92 * 263)
    nbuild = nbuild + 1
    if not vb then nlate = nlate + 1 end
    if e > maxend then maxend = e end
    ev[#ev + 1] = string.format("build %d-%d (%d lines)%s", bstart, e, len, vb and "" or " LATE")
  end
  return d end
TA = mem:install_read_tap(S.FrameShowA, S.FrameShowA, "bt1", done)
TB2 = mem:install_read_tap(S.FrameShowB, S.FrameShowB, "bt2", done)
TD = mem:install_read_tap(S.NmiDliNot, S.NmiDliNot, "bt3", function(a, d)
  if a == pc() and f >= FROM and mem:read_u8(S.S_INVBI) ~= 0 then dropped = dropped + 1 end
  return d end)
-- (this build's) top zones left without a slot of their own
local noslot = 0
if S.TopEmitNoSlot then
  TN = mem:install_read_tap(S.TopEmitNoSlot, S.TopEmitNoSlot, "bt4", function(a, d)
    if a == pc() and f >= FROM and mem:read_u8(S.S_BANK) == 6 then noslot = noslot + 1 end
    return d end)
end
-- (this build's) top refreshes (TopRefresh, in the art bank), and those
-- ending outside the vertical blank
local nref, nreflate, inref, nrefvbi = 0, 0, false, 0
local function art() return mem:read_u8(S.S_BANK) == 6 end
if S.TopRef2 then
  TR1 = mem:install_read_tap(S.TopRef2, S.TopRef2, "bt5", function(a, d)
    if a == pc() and art() and f >= FROM then
      inref = true; nref = nref + 1
      if mem:read_u8(S.S_INVBI) ~= 0 then nrefvbi = nrefvbi + 1 end
    end
    return d end)
  TR2 = mem:install_read_tap(S.TopRefRts, S.TopRefRts, "bt6", function(a, d)
    if a == pc() and art() and inref then
      inref = false
      if (mem:read_u8(0x28) & 0x80) == 0 then nreflate = nreflate + 1; ev[#ev + 1] = "refresh LATE" else ev[#ev + 1] = "refresh" end
    end
    return d end)
end
local o = io.open("buildtime.log", "w")
emu.register_frame_done(function()
  t0 = M.time:as_double()
  f = f + 1
  if f >= FROM then
    if dropped > 0 then ndrop = ndrop + dropped; dropframes = dropframes + 1; ev[#ev + 1] = "dropped " .. dropped end
    if #ev > 0 then o:write(string.format("f%d %s\n", f, table.concat(ev, " "))) end
    ev, dropped = {}, 0
  end
  if f >= END then
    o:write(string.format("builds %d, ending outside the vertical blank %d, latest end line %d; DLIs dropped %d in %d frames; top zones without a slot %d; refreshes %d (in the vertical blank %d), late %d\n",
      nbuild, nlate, maxend, ndrop, dropframes, noslot, nref, nrefvbi, nreflate))
    o:close(); M:exit()
  end
end)

if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
