-- a recorded game forced onto this build (FINDINGS "Replaying a recording
-- on another build"): STATEBIN (p7800-staterec.lua's state.bin, from the
-- recording's own cartridge) and STATE (the address list it used); at each
-- TopFlip entry (every flip) once play has started ($D0 not 0), from flip FROM (default 1)
-- on, that flip's record written back, so the game goes on from the
-- recorded state whatever this build's speed. The recording itself plays
-- along (its inputs between flips). SNAPF: snapshots of those flips'
-- pictures (as playkey.lua's SNAPDL). Stops after the records or END frames.
-- SPALSO: another probe run alongside (one that doesn't load playkey.lua)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "40000")
local FROM = tonumber(os.getenv("FROM") or "1")
-- UNTIL: the last flip forced; after it the game goes its own way on the
-- recording's inputs (e.g. through a stretch forcing spoils: level 2's band)
local UNTIL = tonumber(os.getenv("UNTIL") or "999999")
local addrs = {}
for l in io.lines(os.getenv("STATE")) do addrs[#addrs + 1] = tonumber(l, 16) end
local blob = io.open(os.getenv("STATEBIN"), "rb"):read("a")
-- SKIP: addresses (hex, comma list) never forced: this build's own pointers
-- (probes/stateskip.py)
local skip = {}
for t in (os.getenv("SKIP") or ""):gmatch("%x+") do skip[tonumber(t, 16)] = true end
local recs = #blob // #addrs
local snapf = {}
for t in (os.getenv("SNAPF") or ""):gmatch("%d+") do snapf[tonumber(t)] = true end
local n, f, forced = 0, 0, 0
local FLOG = os.getenv("FLIPLOG") and io.open("flips.txt", "w")   -- FLIPLOG=1: the first flips' frames
local FLIPN = tonumber(os.getenv("FLIPN") or "20")             -- (how many: FLIPN)
-- DIFFLOG=1: each flip's game-state bytes that differ from the record before
-- it is forced (this build's own, recorded) to diffs.txt: where its game
-- went its own way (the recording's inputs read at other moments)
local DLOG = os.getenv("DIFFLOG") and io.open("diffs.txt", "w")
local dpp, at, wait, due = {[0x2C] = 0, [0x30] = 0}, nil, false, false
TW = mem:install_write_tap(0x2C, 0x30, "spd", function(a, d)
  if a ~= 0x2C and a ~= 0x30 then return end
  dpp[a] = d
  if wait and dpp[0x2C] * 256 + dpp[0x30] ~= at then wait = false; due = true end
end)
-- (_G.PROBE_PEEK: a companion reading memory itself, e.g. the instruction at
-- PC: not the CPU's fetch)
T1 = mem:install_read_tap(S.TopFlip, S.TopFlip, "sp1", function(a, d)
  if _G.PROBE_PEEK or a ~= cpu.state["PC"].value or mem:read_u8(0xD0) == 0 then return d end
  n = n + 1
  _G.STATEPLAY_N = n        -- (for an ALSO probe: the autoboot script has its own globals)
  if FLOG and n <= FLIPN then FLOG:write(string.format("%d %d\n", n, f)); FLOG:flush() end
  if n >= FROM and n <= recs and n <= UNTIL then
    local base = (n - 1) * #addrs
    if DLOG then      -- (DIFFLOG=1: the bytes this build's own game differs in, before)
      local t = {}
      for i = 1, #addrs do
        local v = mem:read_u8(addrs[i])
        if not skip[addrs[i]] and v ~= blob:byte(base + i) then
          t[#t + 1] = string.format("%04X:%02X/%02X", addrs[i], v, blob:byte(base + i))
        end
      end
      if #t > 0 then DLOG:write(string.format("%d f%d %s\n", n, f, table.concat(t, " "))) end
    end
    for i = 1, #addrs do
      if not skip[addrs[i]] then mem:write_u8(addrs[i], blob:byte(base + i)) end
    end
    forced = forced + 1
  end
  if snapf[n] then wait = true; at = dpp[0x2C] * 256 + dpp[0x30] end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if due then due = false; M.video:snapshot() end
  -- (PASTEND=1: on after the last record, the game left to itself till END:
  -- what follows a recording's end, e.g. the gate's death that hung a cart)
  if f >= END or (n > recs and not os.getenv("PASTEND")) then
    local l = io.open("stateplay.log", "w")
    l:write(string.format("%d flips, %d forced, of %d recorded\n", n, forced, recs))
    l:close()
    if DLOG then DLOG:close() end
    M:exit()
  end
end)
if os.getenv("SPALSO") then dofile(os.getenv("PROBES") .. "/" .. os.getenv("SPALSO")) end
