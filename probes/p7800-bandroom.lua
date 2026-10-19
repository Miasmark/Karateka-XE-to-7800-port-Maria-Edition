-- the band lists' room (FINDINGS "The fighters as objects: step 4"): for
-- each list refresh (BandRefresh to BandRefDone, in bank 5), the buffer, the
-- zones, the bytes used (S_BDLP's last place less the buffer's start, page
-- heads counted) and the zones whose fighter objects were dropped for room
-- (BandWDrop: the front boxes, then objects, left out; the zone's index, its
-- objects and bytes before).
-- Each zone as zone:objects/bytes@place's low byte (ZONES=1).
-- One line a refresh with drops (all with ALL=1), to bandroom.log, and a
-- summary at the end. Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local ALL = os.getenv("ALL")
local o = io.open("bandroom.log", "w")
local function b(a) return mem:read_u8(a) end
local function pc() return cpu.state["PC"].value end
local function bank5() return b(S.S_BANK) == 5 end
local cur, f, nref, ndrop, most = nil, 0, 0, 0, 0
T1 = mem:install_read_tap(S.BandRefresh, S.BandRefresh, "br1", function(a, d)
  if a == pc() and bank5() then cur = { buf = b(S.S_FBUF), drops = {} } end
  return d end)
T2 = mem:install_read_tap(S.BandWDrop, S.BandWDrop, "br2", function(a, d)
  if a == pc() and bank5() and cur and b(S.S_FW) ~= 0 then
    cur.drops[#cur.drops + 1] = string.format("z%d(%d obj, %d bytes)", b(S.S_FTK), b(S.S_FW), b(S.S_FL0))
  end
  return d end)
T4 = mem:install_read_tap(S.BandWFit, S.BandWFit, "br4", function(a, d)
  if a == pc() and bank5() and cur then
    if not os.getenv("ZONES") then return d end
    cur.z = cur.z or {}
    cur.z[#cur.z + 1] = string.format("%d:%d/%d@%02X", b(S.S_FTK), b(S.S_FW), b(S.S_FL0), b(S.S_BDLP))
  end
  return d end)
T3 = mem:install_read_tap(S.BandRefDone, S.BandRefDone, "br3", function(a, d)
  if a == pc() and bank5() and cur then
    local start = cur.buf == 0 and S.BAND_A or S.BAND_B
    local used = b(S.S_BDLP) + 256 * b(S.S_BDLP + 1) - start
    nref = nref + 1
    if used > most then most = used end
    if #cur.drops > 0 then ndrop = ndrop + 1 end
    if ALL or #cur.drops > 0 then
      o:write(string.format("flip %d frame %d buf %d zones %d used %d: %s\n", PLAYKEY_N or 0, f, cur.buf,
        b(S.S_ZTN + cur.buf), used, table.concat(cur.drops, " ")))
      if cur.z then o:write("  " .. table.concat(cur.z, " ") .. "\n") end
    end
    cur = nil
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    o:write(string.format("refreshes %d, with drops %d, most bytes %d (A %d, B %d)\n", nref, ndrop, most,
      S.BAND_AEND - S.BAND_A, S.BAND_BEND - S.BAND_B))
    o:close()
    if os.getenv("NOPLAY") then M:exit() end
  end
end)
-- NOPLAY=1: no scripted player (a recording played back)
if not os.getenv("NOPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
