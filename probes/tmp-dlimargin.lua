-- (debug) a companion of p7800-stateplay.lua (SPALSO): from flip WFROM to
-- WTO, each NMI's arrival and each game DLI handler's start and end, in
-- lines after the frame's vertical blank NMI (by machine time: this MAME's
-- Lua has no beam line; a line 1/(60*263) s near enough). Per NMI count:
-- the earliest/latest arrival, the handler's start/end, and the margin from
-- a handler's end to the next NMI, to dlimargin.log (FINDINGS "The
-- flickering arrows": how close the music DLI's tick comes to the status
-- bar's colour DLI)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local F0, F1 = tonumber(os.getenv("WFROM") or "0"), tonumber(os.getenv("WTO") or "0")
local log = io.open("dlimargin.log", "w")
local LINE = 1 / (59.92 * 263)
local t0 = nil
local function now() return M.time:as_double() end
local function ln() if t0 then return (now() - t0) / LINE end end
local function on()
  local f = _G.STATEPLAY_N or -1
  return f >= F0 and f <= F1
end
local st = {}   -- st[count] = {arr = {min,max}, beg = {min,max}, fin = {min,max}, gap = {min}}
local function upd(c, k, v)
  st[c] = st[c] or {}
  local e = st[c][k]
  if not e then st[c][k] = { v, v, 1 } else
    if v < e[1] then e[1] = v end
    if v > e[2] then e[2] = v end
    e[3] = e[3] + 1
  end
end
local lastfin = nil
local function tap(name, fn)
  local a = S[name]
  _G["DLM_" .. name] = mem:install_read_tap(a, a, "dlm" .. name, function(ad, d)
    if cpu.state["PC"].value == a then fn() end
    return d
  end)
end
tap("NmiVbi", function() t0 = now() end)
tap("NmiGo", function()
  if not on() or not t0 then return end
  local c = mem:read_u8(S.S_NMICOUNT) + 1
  local l = ln()
  upd(c, "arr", l)
  if lastfin then upd(c, "gap", l - lastfin[2]); lastfin = nil end
end)
tap("NmiDliRun", function()
  if on() and t0 then upd(mem:read_u8(S.S_NMICOUNT), "beg", ln()) end
end)
tap("DliExit", function()
  if on() and t0 then
    local c = mem:read_u8(S.DLI_NUM)
    upd(c, "fin", ln()); lastfin = { c, ln() }
  end
end)
DLM_STOPPER = emu.add_machine_stop_notifier(function()
  for c = 1, 9 do
    if st[c] then
      local parts = { "count " .. c }
      for _, k in ipairs({ "arr", "beg", "fin", "gap" }) do
        local e = st[c][k]
        if e then parts[#parts + 1] = string.format("%s %.1f-%.1f (%d)", k, e[1], e[2], e[3]) end
      end
      log:write(table.concat(parts, "  ") .. "\n")
    end
  end
  log:close()
end)
