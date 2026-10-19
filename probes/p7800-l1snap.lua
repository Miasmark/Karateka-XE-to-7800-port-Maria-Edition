-- level 1's pictures along a run: a snapshot at TopFlip every STEP flips from
-- FROMF, with the view ($52, $50), the structure ($4C) and $E4, $51 to
-- l1snap.log (one line a snapshot, in snapshot order). Runs playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROMF = tonumber(os.getenv("FROMF") or "190")
local STEP = tonumber(os.getenv("STEP") or "20")
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local function zp(x) return mem:read_u8(ZM[x]) end
local o = io.open("l1snap.log", "w")
local want, k = nil, 0
T5 = mem:install_read_tap(S.TopFlip, S.TopFlip, "l1s", function(a, d)
  if a ~= cpu.state["PC"].value then return d end
  local n = PLAYKEY_N or 0
  if n >= FROMF and (n - FROMF) % STEP == 0 and want ~= n then
    want = n
    o:write(string.format("%d flip %d v52 %d v50 %d s4C %d E4 %d 51 %d E0 %d\n", k, n, zp(0x52), zp(0x50), zp(0x4C),
      zp(0xE4), zp(0x51), zp(0xE0)))
    k = k + 1
    snapwait = 2
  end
  return d
end)
emu.register_frame_done(function()
  if snapwait then snapwait = snapwait - 1; if snapwait == 0 then snapwait = nil; M.video:snapshot() end end
  o:flush()
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
