-- how often a fighter's parts could be reused (FINDINGS "The fighters as
-- objects: speed"): at each emit that makes objects (FtEmitP, in bank 5),
-- each recorded fighter of the buffer against the same buffer's last emit:
-- the same pose ($20 lower, $21 upper, $3E type, $36), and also the same
-- place ($22 column, $50 eighths). Counts to ftsame.log at the end.
-- SEQ=1: each emit to ftseq.log: the buffer, then each fighter as
-- slot:lower,upper,type,$36,column,eighths/columns its lower body took,
-- columns its upper body took (each part's from FtEmitPK2 to FtEmitPN).
-- Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local function b(a) return mem:read_u8(a) end
local function on5(a) return a == cpu.state["PC"].value and b(S.S_BANK) == 5 end
local last = {}
local seq = os.getenv("SEQ") and io.open("ftseq.log", "w")
local cur, buf, part, c0, cols = nil, 0, 0, 0, {}
local n, pose, place, emits, skips, f = 0, 0, 0, 0, 0, 0
T1 = mem:install_read_tap(S.FtEmitP, S.FtEmitP, "fs1", function(a, d)
  if not on5(a) then return d end
  emits = emits + 1
  buf = b(S.S_FBUF)
  cur, cols = {tostring(buf)}, {}
  for s = 0, 1 do
    local x = 2 * buf + s
    if b(S.FR_V + x) ~= 0 then
      local k = string.format("%d %d %d %d", b(S.FR_20 + x), b(S.FR_21 + x), b(S.FR_3E + x), b(S.FR_36 + x))
      local p = k .. string.format(" %d %d", b(S.FR_22 + x), b(S.FR_50 + x))
      n = n + 1
      if last[x] and last[x][1] == k then pose = pose + 1 end
      if last[x] and last[x][2] == p then place = place + 1 end
      last[x] = {k, p}
    else
      last[x] = nil
    end
  end
  return d end)
T3 = mem:install_read_tap(S.FtEmitPK2, S.FtEmitPK2, "fs3", function(a, d)
  if on5(a) then part = b(S.FP_PART); c0 = b(S.S_FCOL) end
  return d end)
T4 = mem:install_read_tap(S.FtEmitPN, S.FtEmitPN, "fs4", function(a, d)
  if on5(a) and cur and b(S.FP_PART) == part then cols[part] = math.abs(b(S.S_FCOL) - c0) end
  return d end)
T6 = mem:install_read_tap(S.FtEmitPD, S.FtEmitPD, "fs6", function(a, d)
  if on5(a) and cur then
    for s = 0, 1 do
      local x = 2 * buf + s
      if b(S.FR_V + x) ~= 0 then
        cur[#cur + 1] = string.format("%d:%d,%d,%d,%d,%d,%d/%d,%d", s, b(S.FR_20 + x), b(S.FR_21 + x),
          b(S.FR_3E + x), b(S.FR_36 + x), b(S.FR_22 + x), b(S.FR_50 + x), cols[2 + s] or 0, cols[s] or 0)
      end
    end
    if seq then seq:write(table.concat(cur, " ") .. "\n") end
    cur = nil
  end
  return d end)
T2 = mem:install_read_tap(S.FtEmitOut, S.FtEmitOut, "fs2", function(a, d)
  if on5(a) then skips = skips + 1 end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    local o = io.open("ftsame.log", "w")
    o:write(string.format("emits %d (and %d out: skipped or done), fighters %d: same pose %d, same pose and place %d\n",
      emits, skips, n, pose, place))
    o:close()
    if seq then seq:close() end
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
