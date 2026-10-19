-- the code each bank runs in the window during play (FINDINGS "A 144K cart:
-- the fit"): every instruction fetched at $8000-$BFFF, by the bank in
-- (S_BANK), not while the story or title is up; to wincode.log at END:
-- "bank addr count" per opcode address. Runs playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local FROM = tonumber(os.getenv("FROM") or "1500")
local f = 0
local hits = {}
local function text_up() return (mem:read_u8(S.S_STORY) | mem:read_u8(S.S_TITLEA) | mem:read_u8(S.S_TITLEB) | mem:read_u8(S.S_OBLANK)) ~= 0 end
local up = true
TX = mem:install_read_tap(0x8000, 0xBFFF, "wc", function(a, d)
  if not up and a == cpu.state["PC"].value then
    local k = mem:read_u8(S.S_BANK) * 65536 + a
    hits[k] = (hits[k] or 0) + 1
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  up = f < FROM or text_up()
  if f == END then
    local o = io.open("wincode.log", "w")
    for k, n in pairs(hits) do o:write(string.format("%d %04X %d\n", k >> 16, k & 0xFFFF, n)) end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
