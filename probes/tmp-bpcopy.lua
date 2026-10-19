-- (debug) needs -debug -debugger script (EXTRA); playkey.lua too: a
-- breakpoint at TpCpDll (the top list's copy's end); each stop with the top
-- bank in where the list stayed in its slot (S_ROWP = S_TDLP: no piece had
-- room) logged: its size, the zone, the buffer's pieces' room left (TP_SGP
-- against TPSG's ends, read from the cart's top bank), the first N
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = SYM_ADDR
local N = tonumber(os.getenv("N") or "20")
local o = io.open("bpcopy.log", "w")
local dbg = M.debugger
local n, armed, stops = 0, false, 0
local function w(a) return mem:read_u8(a) + 256 * mem:read_u8(a + 1) end
RU_BC = emu.add_machine_frame_notifier(function()
  if not armed and dbg then cpu.debug:bpset(S.TpCpDll, "1", ""); armed = true end
end)
RU_BCP = emu.register_periodic(function()
  if not dbg or dbg.execution_state ~= "stop" then return end
  stops = stops + 1
  if mem:read_u8(S.S_BANK) == 5 and w(S.S_ROWP) == w(S.S_TDLP) and n < N then
    n = n + 1
    local sg = mem:read_u8(S.TP_SG)
    o:write(string.format("flip %d: %d bytes, zone %d+%d, TP_SG %d, room:", _G.PLAYKEY_N or 0,
      mem:read_u8(S.S_ETMP), mem:read_u8(S.S_ARG), mem:read_u8(S.S_H), sg))
    for k = 0, 6 do
      local hi = mem:read_u8(S.TPSG_SH + sg + k)
      if hi == 0 then break end
      local e = mem:read_u8(S.TPSG_EL + sg + k) + 256 * mem:read_u8(S.TPSG_EH + sg + k)
      o:write(string.format(" %d", e - w(S.TP_SGP + 2 * k)))
    end
    o:write("\n")
    o:flush()
  end
  dbg.execution_state = "run"
end)
RU_BCS = emu.add_machine_stop_notifier(function()
  o:write(string.format("stops %d, logged %d\n", stops, n))
  o:close()
end)
