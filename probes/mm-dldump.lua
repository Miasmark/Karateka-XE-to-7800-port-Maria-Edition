-- Midnight Mutants (or any 7800 cart): presses fire at frames 400-1300, then walks right/up;
-- logs CHARBASE and bank-register writes per frame and dumps the DLL with each zone's
-- headers at frames DUMPS (default 1600,1610,1700,2400), to mmdl.txt; a snapshot every
-- 300 frames. Run with -autoboot_script on the cart, windowless.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local reg = {[0x2C] = 0, [0x30] = 0, [0x34] = 0, [0x3C] = 0}
local f = 0
local banks, chb = {}, {}
TREG = mem:install_write_tap(0x2C, 0x3C, "r", function(a, d)
  if reg[a] then reg[a] = d end
  if a == 0x34 then chb[#chb + 1] = string.format("%02X@%04X", d, cpu.state["PC"].value) end
end)
TBANK = mem:install_write_tap(0x8000, 0xBFFF, "b", function(a, d)
  banks[#banks + 1] = string.format("%02X@%04X", d, cpu.state["PC"].value)
end)
local o = io.open("mmdl.txt", "w")
local function rd(a) return mem:read_u8(a & 0xFFFF) end
local DUMP = {}
for v in (os.getenv("DUMPS") or "1600,1610,1700,2400"):gmatch("%d+") do DUMP[tonumber(v)] = true end
local function press(field, on)
  for tag, port in pairs(M.ioport.ports) do
    local fl = port.fields[field]
    if fl then fl:set_value(on and 1 or 0) end
  end
end
emu.register_frame_done(function()
  f = f + 1
  for _, k in ipairs({400, 700, 1000, 1300}) do
    if f == k then press("P1 Button 1", true) elseif f == k + 8 then press("P1 Button 1", false) end
  end
  if f >= 1450 then press(((f // 200) % 2 == 0) and "P1 Right" or "P1 Up", true); press(((f // 200) % 2 == 0) and "P1 Up" or "P1 Right", false) end
  if f % 300 == 0 then M.video:snapshot() end
  if DUMP[f] then
    o:write(string.format("== frame %d DLL %02X%02X CHARBASE %02X CTRL %02X\n", f, reg[0x2C], reg[0x30], reg[0x34], reg[0x3C]))
    o:write("   CHARBASE writes this frame: " .. table.concat(chb, " ") .. "\n")
    o:write("   bank writes this frame: " .. table.concat(banks, " ") .. "\n")
    local dll = reg[0x2C] * 256 + reg[0x30]
    local line = 0
    for e = 0, 40 do
      local fl, hi, lo = rd(dll + 3 * e), rd(dll + 3 * e + 1), rd(dll + 3 * e + 2)
      local dl = hi * 256 + lo
      local hs = {}
      local p = dl
      for n = 1, 8 do
        local b1 = rd(p + 1)
        if b1 == 0 then break end
        if (b1 & 0x1F) == 0 then hs[#hs + 1] = string.format("[%02X %02X %02X %02X %02X]", rd(p), b1, rd(p + 2), rd(p + 3), rd(p + 4)); p = p + 5
        else hs[#hs + 1] = string.format("[%02X %02X %02X %02X]", rd(p), b1, rd(p + 2), rd(p + 3)); p = p + 4 end
      end
      o:write(string.format("   z%02d line %3d flags %02X lines %2d dl %04X %s\n", e, line, fl, (fl & 15) + 1, dl, table.concat(hs, " ")))
      line = line + (fl & 15) + 1
      if line >= 243 then break end
    end
    o:flush()
  end
  banks, chb = {}, {}
  if f >= tonumber(os.getenv("END") or "2500") then M:exit() end
end)
