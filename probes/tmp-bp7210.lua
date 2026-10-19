-- (debug) needs -debug -debugger script (EXTRA); playkey.lua too: breakpoints
-- at every address BPLO-BPHI (default $7000-$73FF, v1's cart RAM around
-- $7210); each stop's frame, PC, banks and stack to bp7210.log. Also MARIA's
-- own reads of $7210 (its DMA space), counted per frame (FINDINGS "v1: the
-- rules MAME's cart RAM fetch")
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = SYM_ADDR
local LO = tonumber(os.getenv("BPLO") or "28672")
local HI = tonumber(os.getenv("BPHI") or "29695")
local o = io.open("bp7210.log", "w")
local dbg = M.debugger
local armed, stops, fr = false, 0, 0
local mr, mfirst = 0, nil
local maria = M.devices[":maria"]
if maria and maria.spaces["dma"] then
  BP_M = maria.spaces["dma"]:install_read_tap(0x7210, 0x7210, "bpm", function(a, d)
    mr = mr + 1
    if not mfirst then mfirst = fr end
    return d
  end)
else
  o:write("no MARIA dma space\n")
end
BP_F = emu.add_machine_frame_notifier(function()
  fr = fr + 1
  if not armed and dbg then
    for a = LO, HI do cpu.debug:bpset(a, "1", "") end
    armed = true
  end
end)
BP_P = emu.register_periodic(function()
  if not dbg or dbg.execution_state ~= "stop" then return end
  stops = stops + 1
  if stops <= 6 then
    local sp = cpu.state["SP"].value & 0xFF
    local st = {}
    for k = 1, 12 do st[#st + 1] = string.format("%02X", mem:read_u8(0x100 + ((sp + k) & 0xFF))) end
    o:write(string.format("stop %d f%d PC $%04X SP %02X S_BANK %02X scene %02X\n  stack %s\n",
      stops, fr, cpu.state["PC"].value, sp, mem:read_u8(S.S_BANK), mem:read_u8(S.G_ZD0), table.concat(st, " ")))
    o:flush()
  end
  dbg.execution_state = "run"
end)
BP_S = emu.add_machine_stop_notifier(function()
  o:write(string.format("stops %d; MARIA's reads of $7210: %d, first at frame %s\n", stops, mr, tostring(mfirst)))
  o:close()
end)
