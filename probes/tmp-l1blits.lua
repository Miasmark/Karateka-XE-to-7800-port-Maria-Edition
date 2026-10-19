-- (debug) a companion of p7800-stateplay.lua (SPALSO), or alone: from frame
-- PFROM, each blit the level's set takes (L1BlitF: its image L1_SRC, row
-- L1_ROW, kind L1B_KIND, column $05), each fill it sees (L1Fill: columns
-- $05-$09, rows $06-$08), each fighter draw (FRecF: $2C negative the enemy,
-- its poses $20/$21/$22, $50, $36, the enemy type $4D), each box erase (ErP,
-- ErE), full clear (ClearBufF) and flip (TopFlip), with the buffer drawn
-- ($07), in order, to l1blits.log (the ghost player in the embrace; the
-- cutscene guard's ghost). ALSO: another probe
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local zp = {}
for l in io.lines(os.getenv("ZPMAP")) do local z, a = l:match("(%x+) (%x+)"); if z then zp[tonumber(z, 16)] = tonumber(a, 16) end end
local FROM = tonumber(os.getenv("PFROM") or "0")
local log = io.open("l1blits.log", "w")
local f = 0
local taps = {}
local function z(a) return mem:read_u8(zp[a]) end
for _, n in ipairs({"L1BlitF", "L1Fill", "FRecF", "ErP", "ErE", "ClearBufF", "TopFlip"}) do
  local a = sym[n]
  if a then
    taps[#taps + 1] = mem:install_read_tap(a, a, "b" .. n, function(ad, d)
      if f >= FROM and ad == cpu.state["PC"].value then
        if n == "L1BlitF" then
          log:write(string.format("f%d blit $07=%02X src %04X row %d kind %02X col %d\n", f, z(0x07),
            mem:read_u8(sym.L1_SRC) + 256 * mem:read_u8(sym.L1_SRC + 1), mem:read_u8(sym.L1_ROW),
            mem:read_u8(sym.L1B_KIND), z(0x05)))
        elseif n == "L1Fill" then
          log:write(string.format("f%d fill $07=%02X cols %d-%d rows %d-%d\n", f, z(0x07), z(0x05), z(0x09),
            z(0x06), z(0x08)))
        else
          log:write(string.format("f%d %s $07=%02X $2C=%02X $20=%02X $21=%02X $22=%02X $50=%02X $36=%02X $4D=%02X\n",
            f, n, z(0x07), z(0x2C), z(0x20), z(0x21), z(0x22), z(0x50), z(0x36), z(0x4D)))
        end
        log:flush()
      end
      return d
    end)
  end
end
L1BLIT_TAPS = taps
emu.register_frame_done(function() f = f + 1 end)
if os.getenv("ALSO") then dofile(os.getenv("PROBES") .. "/" .. os.getenv("ALSO")) end
