-- the parts' reuse (FINDINGS "The fighters as objects: speed"), flips FROM
-- to AT: each part's decision at the emit (FtEmitPK2: buffer, part, in
-- place or copied, its key and first column) and each write to the slice
-- pages' columns C0-C1 (page $73-$7A; the writer's PC and bank), to
-- reuselog.log. Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local AT = tonumber(os.getenv("AT") or "1280")
local FROM = tonumber(os.getenv("FROM") or AT - 6)
local C0, C1 = tonumber(os.getenv("C0") or "56"), tonumber(os.getenv("C1") or "75")
local o = io.open("reuselog.log", "w")
local function b(a) return mem:read_u8(a) end
local function on() local n = PLAYKEY_N or 0; return n >= FROM and n <= AT end
T1 = mem:install_read_tap(S.FtEmitPK2, S.FtEmitPK2, "rl1", function(a, d)
  if a == cpu.state["PC"].value and b(S.S_BANK) == 5 and on() then
    o:write(string.format("flip %d buf %d part %d %s key %d,%d col %d\n", PLAYKEY_N, b(S.S_FBUF), b(S.FP_PART),
      b(S.FP_NOCP) ~= 0 and "in place" or "copied", b(S.FP_K1), b(S.FP_K2), b(S.S_FCOL)))
  end
  return d end)
local last = {}
T2 = mem:install_write_tap(0x7300, 0x7AFF, "rl2", function(a, d)
  local c = a & 0xFF
  if c < C0 or c > C1 or not on() then return end
  local k = string.format("flip %d write $%02Xxx cols %d-%d PC $%04X bank %d", PLAYKEY_N, a >> 8, C0, C1,
    cpu.state["PC"].value, b(S.S_BANK))
  if last[1] ~= k then o:write(k .. "\n"); last[1] = k end
end)
emu.register_frame_done(function() if (PLAYKEY_N or 0) > AT then o:flush() end end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
