-- every fighter part's columns (FINDINGS "The fighters as objects: speed"):
-- at each emit (FtEmitP, bank 5) the buffer's records are overwritten with
-- the next combination, one fighter at a time (the other's record off), at
-- column 16 so nothing is cut: the player's lower poses 0-41 alongside its
-- upper poses 0-37 with $36 0, then with $36 set for each type 0-6; then the
-- enemy's, each type 0-6. The columns each part took (S_FCOL from FtEmitPK2
-- to FtEmitPN) to ftmax.log, and the most per class at the end. Runs
-- playkey.lua (its env applies); stops when done or at END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "20000")
local function b(a) return mem:read_u8(a) end
local function w(a, v) mem:write_u8(a, v) end
local function on5(a) return a == cpu.state["PC"].value and b(S.S_BANK) == 5 end
local combos = {}
for u = 0, 37 do combos[#combos + 1] = {0, u, 0, 0} end
for t = 0, 6 do for u = 0, 37 do combos[#combos + 1] = {0, u, t, 1} end end
for t = 0, 6 do for u = 0, 37 do combos[#combos + 1] = {1, u, t, 0} end end
local o = io.open("ftmax.log", "w")
local i, cur, c0, cl, f = 0, nil, 0, 0, 0
local most = {}
local function note(k, v) if not most[k] or v > most[k][1] then most[k] = {v, cur} end end
T1 = mem:install_read_tap(S.FtEmitP, S.FtEmitP, "fm1", function(a, d)
  if not on5(a) or i >= #combos then return d end
  i = i + 1
  local c = combos[i]
  local buf = b(S.S_FBUF)
  local x = 2 * buf + c[1]
  w(S.FR_V + 2 * buf + 1 - c[1], 0)
  w(S.FR_V + x, 2)
  w(S.FR_20 + x, (i - 1) % 42)
  w(S.FR_21 + x, c[2]); w(S.FR_3E + x, c[3]); w(S.FR_36 + x, c[4])
  w(S.FR_22 + x, 16); w(S.FR_50 + x, 0)
  cur = {slot = c[1], l = (i - 1) % 42, u = c[2], t = c[3], f36 = c[4]}
  return d end)
local part, c0, cols = 0, 0, {}
T3 = mem:install_read_tap(S.FtEmitPK2, S.FtEmitPK2, "fm3", function(a, d)
  if on5(a) then part = b(S.FP_PART); c0 = b(S.S_FCOL) end
  return d end)
T4 = mem:install_read_tap(S.FtEmitPN, S.FtEmitPN, "fm4", function(a, d)
  if on5(a) and b(S.FP_PART) == part then cols[part] = math.abs(b(S.S_FCOL) - c0) end
  return d end)
T5 = mem:install_read_tap(S.FtEmitPD, S.FtEmitPD, "fm5", function(a, d)
  if on5(a) and cur then
    local lc, uc = cols[2 + cur.slot] or 0, cols[cur.slot] or 0
    o:write(string.format("slot %d lower %d upper %d type %d $36 %d: lower %d upper %d\n",
      cur.slot, cur.l, cur.u, cur.t, cur.f36, lc, uc))
    note("L" .. cur.slot, lc); note("U" .. cur.slot, uc)
    cur, cols = nil, {}
  end
  return d end)
local function finish()
  for k, v in pairs(most) do
    o:write(string.format("most %s: %d\n", k, v[1]))
  end
  o:close()
  M:exit()
end
emu.register_frame_done(function()
  f = f + 1
  if (i >= #combos and not cur) or f >= END then finish() end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
