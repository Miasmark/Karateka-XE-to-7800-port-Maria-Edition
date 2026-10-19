-- (debug) each capture TopCapture finds (TopCapFound runs, an opcode fetch):
-- the frame, the piece (X), the game's column ($05), shift ($10), the
-- capture's mirroring (S_TMIR) and right-byte column (S_TRAL), for pieces
-- PLO-PHI, frames FROM-TO, to jointcap.log; MAME exits at TO (FINDINGS
-- "Level 2's windows")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local AT = sym.TopCapFound
local PLO, PHI = tonumber(os.getenv("PLO") or "59"), tonumber(os.getenv("PHI") or "62")
local FROM, TO = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("TO") or "99999")
local f = 0
local log = io.open("jointcap.log", "w")
JC_TAP = mem:install_read_tap(AT, AT, "jcap", function(a, d)
  if f >= FROM and cpu.state["PC"].value == AT then
    local x = cpu.state["X"].value
    if x >= PLO and x <= PHI then
      log:write(string.format("f%d piece %d col %d shift %d mir %02X ral %02X\n", f, x,
        mem:read_u8(sym.G_Z05), mem:read_u8(sym.G_Z10), mem:read_u8(sym.S_TMIR), mem:read_u8(sym.S_TRAL)))
    end
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f >= TO then log:close(); M:exit() end
end)
