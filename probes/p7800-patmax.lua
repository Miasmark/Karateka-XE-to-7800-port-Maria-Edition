-- the most patched-list slots (sys7800 StoryPatch, two a page) one picture's
-- lists take, per buffer: from the writes of S_SPAT/S_SPAT+1 (the next slot),
-- against the areas STORY_PATA/STORY_PATB (STORY_PATN pages each; from SYM);
-- to patmax.log at frame END. WITH: another probe to run first (dofile)
if os.getenv("WITH") then dofile(os.getenv("PROBES") .. "/" .. os.getenv("WITH")) end
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local SP, PA, PB, PN = sym.S_SPAT, sym.STORY_PATA, sym.STORY_PATB, sym.STORY_PATN or 4
local ENDF = tonumber(os.getenv("END") or "300")
local best, whenA, whenB, f = {A = 0, B = 0}, 0, 0, 0
local function note()
  local lo, hi = mem:read_u8(SP), mem:read_u8(SP + 1)
  local k, base
  if hi >= PA and hi < PA + PN then k, base = "A", PA elseif hi >= PB and hi < PB + PN then k, base = "B", PB else return end
  local slot = (hi - base) * 2 + (lo >= 128 and 1 or 0)   -- the next free slot = slots taken
  if slot > best[k] then best[k] = slot; if k == "A" then whenA = f else whenB = f end end
end
PT1 = mem:install_write_tap(SP, SP + 1, "spat", function(a, d) return d end)
PT2 = mem:install_write_tap(SP, SP + 1, "spat2", function(a, d) note(); return d end)
emu.register_frame_done(function()
  f = f + 1
  note()
  if f == ENDF - 1 then
    local o = io.open("patmax.log", "w")
    o:write(string.format("most slots taken: A %d (frame %d), B %d (frame %d), of %d each\n", best.A, whenA, best.B, whenB, 2 * PN))
    o:close()
  end
end)
