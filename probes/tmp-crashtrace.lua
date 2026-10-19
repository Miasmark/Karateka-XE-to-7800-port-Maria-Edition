-- (debug) a companion of p7800-stateplay.lua (SPALSO), under MAME's -debug:
-- the CPU's trace from frame TFROM (MAME's "trace" command, to trace.log)
-- till it runs at an address below $0100 (zero page: the crash), then a
-- few more frames and stop (the forced replay of recording 07 on V2 ending at
-- PC $0065 in level 2)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local dbg = M.debugger
local FROM = tonumber(os.getenv("TFROM") or "0")
local f, on, hit = 0, false, nil
emu.register_frame_done(function()
  f = f + 1
  if f == FROM and dbg then
    dbg:command("trace trace.log,maincpu,noloop")
    dbg:command("go")
    on = true
  end
  if on and not hit and cpu.state["PC"].value < 0x100 then hit = f end
  if hit and f >= hit + 2 then
    dbg:command("trace off,maincpu")
    M:exit()
  end
end)
