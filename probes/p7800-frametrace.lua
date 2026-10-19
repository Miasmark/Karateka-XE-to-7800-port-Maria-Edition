-- from frame FROM to TO: each frame's calls of the frame routine (Frame,
-- FrameGo), BuildDll and ObjBlank (from SYM), and at its end S_DLIST,
-- S_CHOSEN, S_OBLANK, S_BUSY, S_STORY and MARIA's DPPH:DPPL, to frametrace.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local A = SYM_ADDR
local FROM, TO = tonumber(os.getenv("FROM")), tonumber(os.getenv("TO"))
local f, ev, dpph, dppl = 0, {}, 0, 0
local log = io.open("frametrace.log", "w")
local function at(name)
  local a = A[name]
  return mem:install_read_tap(a, a, "t" .. name, function(ad, d)
    if f >= FROM and ad == cpu.state["PC"].value then ev[#ev + 1] = name end
    return d end)
end
T = {at("Frame"), at("FrameGo"), at("BuildDll"), at("ObjBlank")}
T[#T + 1] = mem:install_write_tap(0x2C, 0x2C, "dh", function(a, d) dpph = d; return d end)
T[#T + 1] = mem:install_write_tap(0x30, 0x30, "dl", function(a, d) dppl = d; return d end)
local function w(a) return mem:read_u8(a) + 256 * mem:read_u8(a + 1) end
emu.register_frame_done(function()
  f = f + 1
  if f >= FROM then
    log:write(string.format("f%d DLIST %04X CHOSEN %04X OBLANK %d BUSY %d STORY %d DPP %02X%02X | %s\n", f,
      w(A.S_DLIST), w(A.S_CHOSEN), mem:read_u8(A.S_OBLANK), mem:read_u8(A.S_BUSY), mem:read_u8(A.S_STORY),
      dpph, dppl, table.concat(ev, " ")))
    ev = {}
  end
  if f >= TO then log:close(); M:exit() end
end)
