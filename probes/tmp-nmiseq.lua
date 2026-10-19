-- (debug) a companion of p7800-stateplay.lua (SPALSO): each frame's NMIs
-- in order, from flip WFROM to WTO (opcode fetches): R<n> the game's DLI
-- handler run (NmiDliRun) at NMI count n, D<n> a DLI dropped (NmiDliNot
-- with no DLI running: in the vertical blank), P<n> one put off (a DLI
-- running), V the vertical blank's start (NmiVbiRun), v its end
-- (NmiVbiDone1), s/S the sky DLIs (NmiSkyOn/Off). To nmiseq.log, a line a
-- frame (FINDINGS "The flickering arrows")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local F0, F1 = tonumber(os.getenv("WFROM") or "0"), tonumber(os.getenv("WTO") or "0")
local log = io.open("nmiseq.log", "w")
local seq = {}
local function on(n)
  local f = _G.STATEPLAY_N or -1
  return f >= F0 and f <= F1
end
local function tap(name, fn)
  local a = S[name]
  if not a then log:write("no symbol " .. name .. "\n"); return end
  _G["NSQ_" .. name] = mem:install_read_tap(a, a, "nsq" .. name, function(ad, d)
    if cpu.state["PC"].value == a and on() then fn() end
    return d
  end)
end
local function cnt() return mem:read_u8(S.S_NMICOUNT) end
tap("NmiDliRun", function() seq[#seq + 1] = "R" .. cnt() end)
tap("NmiDliNot", function()
  if mem:read_u8(S.S_INDLI) == 0 then seq[#seq + 1] = "D" .. cnt() else seq[#seq + 1] = "P" .. cnt() end
end)
tap("NmiVbiRun", function() seq[#seq + 1] = "V" end)
tap("NmiVbiDone1", function() seq[#seq + 1] = "v" .. cnt() end)
tap("NmiSkyOn", function() seq[#seq + 1] = "s" end)
tap("NmiSkyOff", function() seq[#seq + 1] = "S" end)
-- (and P1C2's writes, w<count>=<value>: the enemy's arrows' colour)
NSQ_W = mem:install_write_tap(0x26, 0x26, "nsqw", function(ad, d)
  if on() then seq[#seq + 1] = string.format("w%d=%02X", cnt(), d) end
  return d
end)
-- (and the game's DLI count's writes, c<count>=<value>@PC: G_L0F14)
NSQ_C = mem:install_write_tap(S.G_L0F14, S.G_L0F14, "nsqc", function(ad, d)
  if on() and d ~= mem:read_u8(S.G_L0F14) + 1 then
    seq[#seq + 1] = string.format("c%d=%02X@%04X", cnt(), d, cpu.state["PC"].value)
  end
  return d
end)
-- (the colour sets' count, $0F0E, e<count>=..., and the scheme, $0F0C, k...)
for _, t in ipairs({ { 0x1A94, "e" }, { 0x1A92, "k" } }) do
  _G["NSQ_" .. t[2]] = mem:install_write_tap(t[1], t[1], "nsq" .. t[2], function(ad, d)
    if on() and d ~= mem:read_u8(t[1]) + 1 and d ~= mem:read_u8(t[1]) then
      seq[#seq + 1] = string.format("%s%d=%02X@%04X", t[2], cnt(), d, cpu.state["PC"].value)
    end
    return d
  end)
end
emu.register_frame_done(function()
  if on() then
    log:write(string.format("n%d %s\n", _G.STATEPLAY_N or -1, table.concat(seq, " ")))
  end
  seq = {}
end)
