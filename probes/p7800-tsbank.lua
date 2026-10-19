-- the title's and story's data read only with bank 0 in (FINDINGS "The title
-- and the opening scroll in bank 0's MARIA copy"): while the title (marks) or
-- the story (S_STORY 2) is up, every read of TS_PAGES ($8F00-$ACFF) that is
-- not the CPU's (not its instruction's fetch nor its effective address) is
-- MARIA's; with another bank in the window it is counted and the first 40
-- logged. The scene's page is the bank wanted (bank 0 for the title and
-- story, bank 4 for the ending). To tsbank.log at END. Runs playkey.lua (the
-- attract loop: K0 off), or with JUMP set p7800-jumpto.lua (WITHPLAY=1).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "4300")
local st = cpu.state
local LO, HI = tonumber(os.getenv("LO") or "8F00", 16), tonumber(os.getenv("HI") or "ACFF", 16)
local function ea(pc)
  local op = mem:read_u8(pc)
  local lo, hi = mem:read_u8(pc + 1), mem:read_u8(pc + 2)
  local x, y = st["X"].value, st["Y"].value
  local cc, bbb = op & 3, (op >> 2) & 7
  local abs = lo + 256 * hi
  if cc == 1 then
    if bbb == 0 then local p = (lo + x) & 0xFF; return mem:read_u8(p) + 256 * mem:read_u8((p + 1) & 0xFF) end
    if bbb == 3 then return abs end
    if bbb == 4 then return (mem:read_u8(lo) + 256 * mem:read_u8((lo + 1) & 0xFF) + y) & 0xFFFF end
    if bbb == 6 then return (abs + y) & 0xFFFF end
    if bbb == 7 then return (abs + x) & 0xFFFF end
  elseif cc == 2 then
    if bbb == 3 then return abs end
    if bbb == 7 then return (abs + ((op == 0xBE) and y or x)) & 0xFFFF end
  elseif cc == 0 then
    if bbb == 3 and op ~= 0x4C and op ~= 0x6C then return abs end
    if bbb == 7 and op == 0xBC then return (abs + x) & 0xFFFF end
  end
  return nil
end
local f, ok, bad, logged = 0, 0, 0, {}
local function on()
  return mem:read_u8(S.S_STORY) == 2 or (mem:read_u8(S.S_TITLEA) | mem:read_u8(S.S_TITLEB)) ~= 0
end
TB = mem:install_read_tap(LO, HI, "tsb", function(a, d)
  if not on() then return d end
  local pc = st["PC"].value
  if a >= pc and a <= pc + 2 then return d end
  local e = ea(pc)
  if e and (e == a or e == ((a - 0x100) & 0xFFFF)) then return d end
  local bank = mem:read_u8(S.S_BANK)
  if bank == mem:read_u8(S.S_SCENEBANK) then ok = ok + 1 else
    bad = bad + 1
    if #logged < 40 then logged[#logged + 1] = string.format("frame %d $%04X bank %d PC %04X", f, a, bank, pc) end
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f == END then
    local o = io.open("tsbank.log", "w")
    o:write(string.format("%d frames: MARIA's reads with the scene's page in %d, with another bank %d\n", f, ok, bad))
    for _, l in ipairs(logged) do o:write(l .. "\n") end
    o:close()
  end
end)
if os.getenv("JUMP") then dofile(os.getenv("PROBES") .. "/p7800-jumpto.lua")
else dofile(os.getenv("PROBES") .. "/playkey.lua") end
