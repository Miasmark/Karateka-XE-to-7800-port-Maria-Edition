-- writes by the blitter (cart RAM $7C00-$7FFF) outside the bitmap, the scratch row and its own code
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local f, n = 0, 0
local o = io.open("blwrites.log", "w")
local CL = S.S_CLIPROW
local function ok(a)
  if a >= 0x6100 and a <= 0x72FF and (a & 0xFF) >= 16 then return true end   -- the bitmap's rows
  if a >= 0x5CD0 and a <= 0x5CFF then return true end                        -- the floor's scratch row
  if a >= CL and a < CL + 48 then return true end
  if a >= 0x7C00 and a <= 0x7FFF then return true end                        -- its own code
  if a >= 0x0040 and a <= 0x01FF then return true end
  return false
end
local function tap(lo, hi, nm)
  return mem:install_write_tap(lo, hi, nm, function(a, d)
    if n >= 200 then return end
    local pc = cpu.state["PC"].value
    if pc >= 0x7C00 and pc <= 0x7FFF and not ok(a) then
      n = n + 1
      o:write(string.format("f%d flip %s PC %04X wrote $%04X = %02X FL_BLIT %02X FROW %d\n", f, tostring(PLAYKEY_N), pc, a, d,
        mem:read_u8(S.FL_BLIT), mem:read_u8(S.FL_FROW)))
      o:flush()
    end
  end)
end
TB1 = tap(0x1800, 0x27FF, "b1")
TB2 = tap(0x4000, 0x7FFF, "b2")
emu.register_frame_done(function() f = f + 1 end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
