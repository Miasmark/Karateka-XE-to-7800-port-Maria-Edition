-- (debug) frames FROM..TO: the frame count, NMI count and VBI number, the
-- handlers' flags, the stub's first bytes, the shown list's table base
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM, TO = tonumber(os.getenv("FROM") or "560"), tonumber(os.getenv("TO") or "620")
local f = 0
local o = io.open("nmiwatch.txt", "w")
emu.register_frame_done(function()
  f = f + 1
  if f < FROM or f > TO then return end
  local b = function(a) return mem:read_u8(a) end
  local st = {}
  for i = 0, 8 do st[#st + 1] = string.format("%02X", b(S.NMI_STUB + i)) end
  o:write(string.format("f%d FRAMES %d NMICOUNT %d NMIVBI %d INVBI %d INDLI %d VBIPEND %d DLIPEND %d NMICHT %d stub %s PC %04X\n",
    f, b(S.S_FRAMES), b(S.S_NMICOUNT), b(S.S_NMIVBI), b(S.S_INVBI), b(S.S_INDLI), b(S.S_VBIPEND), b(S.S_DLIPEND),
    b(S.S_NMICHT), table.concat(st, " "), M.devices[":maincpu"].state["PC"].value))
  o:flush()
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
