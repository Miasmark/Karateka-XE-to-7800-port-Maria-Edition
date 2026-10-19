-- every image the game blits (FINDINGS "A 144K cart: the scenery's
-- graphics"): at BlitBank (each blit's header read, $29DC) the blitter's
-- kind from its caller's return (TOP_RETA normal, BL_RETAR right-aligned,
-- TOP_RETM mirrored, TOP_RETMR mirrored right-aligned) and FT_IN (1 a
-- fighter's part: dropped, counted as /ft; 2 Akuma's, 3 the hawk's: captured); at its end
-- (BlitBankKeep, the bank chosen) the image's place (the bank in, or RAM,
-- or the fixed bank) and its header (rows, bytes a row). Fighter parts that
-- leave early are counted by FT_IN only. Each distinct image once, with its
-- uses and the flips it was drawn in, to blitcensus.log at END: "kind bank
-- src rows width mode uses flips rows-drawn-at". Not while the story or title is up
-- (TEXT=1: those too). Runs playkey.lua unless NOPLAY (as p7800-stateplay.lua's
-- SPALSO).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local function zp(x) return mem:read_u8(ZM[x]) end
local END = tonumber(os.getenv("END") or "6000")
local TEXT = os.getenv("TEXT")
local KIND = {[0x7C50] = "A", [0x7DC4] = "AR", [0x7F84] = "M", [0x7F8D] = "MR"}
local pend = nil
local seen = {}
local fighters = 0
local f = 0
local function text_up() return (mem:read_u8(S.S_STORY) | mem:read_u8(S.S_TITLEA) | mem:read_u8(S.S_TITLEB) | mem:read_u8(S.S_OBLANK)) ~= 0 end
T1 = mem:install_read_tap(S.BlitBank, S.BlitBank, "bc1", function(a, d)
  if a ~= cpu.state["PC"].value then return d end
  if not TEXT and text_up() then pend = nil; return d end
  local sp = cpu.state["SP"].value & 0xFF
  local ret = mem:read_u8(0x103 + sp) + 256 * mem:read_u8(0x104 + sp)
  local ftin = mem:read_u8(S.FT_IN)
  if ftin == 1 then fighters = fighters + 1 end
  pend = {kind = (KIND[ret] or string.format("?%04X", ret)) .. (ftin == 1 and "/ft" or (ftin >= 2 and ("/cap" .. ftin) or "")), mode = zp(0x0F),
          row = (zp(0x06) - 0x23) & 0xFF}
  return d
end)
local function keep(a, d)
  if a ~= cpu.state["PC"].value or not pend then return d end
  local src = zp(0x04) * 256 + zp(0x03)
  local where
  if src >= 0xC000 then where = "fixed"
  elseif src >= 0x8000 then where = string.format("b%d", mem:read_u8(S.S_BANK))
  else where = "ram" end
  local rows, w = mem:read_u8(src), mem:read_u8(src + 1)
  local k = string.format("%s %s %04X %d %d %02X", pend.kind, where, src, rows, w, pend.mode)
  local e = seen[k]
  if not e then e = {n = 0, flips = {}, nf = 0, rows = {}}; seen[k] = e end
  e.n = e.n + 1
  e.rows[pend.row] = true
  local fl = PLAYKEY_N or -1
  if not e.flips[fl] then e.flips[fl] = true; e.nf = e.nf + 1 end
  pend = nil
  return d
end
T2 = mem:install_read_tap(S.BlitBankKeep, S.BlitBankKeep, "bc2", keep)
T3 = mem:install_read_tap(S.BlitBankX, S.BlitBankX, "bc3", keep)   -- (captured: Akuma's, the hawk's)
emu.register_frame_done(function()
  f = f + 1
  if f == END then
    local o = io.open("blitcensus.log", "w")
    o:write(string.format("fighter parts (FT_IN 1) %d\n", fighters))
    for k, e in pairs(seen) do
      local rs = {}
      for r in pairs(e.rows) do rs[#rs + 1] = r end
      table.sort(rs)
      o:write(string.format("%s %d %d %s\n", k, e.n, e.nf, table.concat(rs, ",")))
    end
    o:close()
  end
end)
if not os.getenv("NOPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
