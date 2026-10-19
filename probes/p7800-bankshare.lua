-- which bank is in the $8000-$BFFF window during play (FINDINGS "Which bank
-- is in the window"): from frame FROM to TO, at every CPU read of
-- $8000-$FFFF, the window's bank (S_BANK) counted, split by where the
-- code doing it runs (PC in the window, in the fixed bank, in RAM), to
-- bankshare.log at TO. Runs playkey.lua (its env applies).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM, TO = tonumber(os.getenv("FROM") or "4000"), tonumber(os.getenv("TO") or "6000")
local f, cnt = 0, {}
local TEXT = os.getenv("TEXT")     -- TEXT=1: only while the title or story is up
TBS = mem:install_read_tap(0x8000, 0xFFFF, "bs", function(a, d)
  if f < FROM or f > TO then return d end
  if TEXT and (mem:read_u8(S.S_STORY) | mem:read_u8(S.S_TITLEA) | mem:read_u8(S.S_TITLEB)) == 0 then return d end
  local pc = cpu.state["PC"].value
  local where = pc >= 0xC000 and "fixed" or (pc >= 0x8000 and "window" or "RAM")
  local k = string.format("bank %d, code in %s", mem:read_u8(S.S_BANK), where)
  cnt[k] = (cnt[k] or 0) + 1
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f == TO then
    local tot, ks = 0, {}
    for k, n in pairs(cnt) do tot = tot + n; ks[#ks + 1] = k end
    table.sort(ks, function(p, q) return cnt[p] > cnt[q] end)
    local o = io.open("bankshare.log", "w")
    for _, k in ipairs(ks) do o:write(string.format("%5.1f%%  %s\n", 100 * cnt[k] / tot, k)) end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
