-- (debug) from frame PFROM to PTO: each instance level 1's set takes out
-- (L1Del: X the instance; its shape L1_SHA,X less 128 plus L1_KB, read while
-- the set's bank is in: image L1K_SHI/SLO, row L1K_ROW, place L1_XA), with
-- what called it (the stack's first two return addresses) and the fill's box
-- ($05-$09, $06-$08); and each fill (L1Fill), blit (L1BlitF), box erase
-- (ErP, ErE) and flip (TopFlip), to l1del.log; MAME stops after PTO (the
-- stairs' striped post lost in level 3's first room)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local zp = {}
for l in io.lines(os.getenv("ZPMAP")) do local z, a = l:match("(%x+) (%x+)"); if z then zp[tonumber(z, 16)] = tonumber(a, 16) end end
local FROM = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local log = io.open("l1del.log", "w")
local f = 0
local function z(a) return mem:read_u8(zp[a]) end
local function b(n, i) return mem:read_u8(sym[n] + (i or 0)) end
local taps = {}
for _, n in ipairs({"L1Del", "L1Fill", "L1BlitF", "ErP", "ErE", "TopFlip"}) do
  local a = sym[n]
  if a then
    taps[#taps + 1] = mem:install_read_tap(a, a, "d" .. n, function(ad, d)
      if f >= FROM and f <= TO and ad == cpu.state["PC"].value then
        local s
        if n == "L1Del" then
          local x = cpu.state["X"].value
          local base = b("L1_B") * 0x30
          local sh = ((b("L1_SHA", x) & 0x7F) + b("L1_KB")) & 0xFF
          local sp = cpu.state["SP"].value
          local function ret(k) return mem:read_u8(0x100 + ((sp + 2 * k - 1) & 0xFF)) + 256 * mem:read_u8(0x100 + ((sp + 2 * k) & 0xFF)) + 1 end
          s = string.format("DEL buf %d inst %d shape %02X%02X row %d x %d (ret %04X %04X) box c%d-%d r%d-%d",
            b("L1_B"), x - base, b("L1K_SHI", sh), b("L1K_SLO", sh), b("L1K_ROW", sh), b("L1_XA", x), ret(1), ret(2),
            z(0x05), z(0x09), z(0x06), z(0x08))
        elseif n == "L1Fill" then
          s = string.format("fill $07=%02X cols %d-%d rows %d-%d PAT=%02X NOFILL=%02X", z(0x07), z(0x05), z(0x09), z(0x06), z(0x08),
            b("L1F_PAT"), b("S_NOFILL"))
        elseif n == "L1BlitF" then
          s = string.format("blit $07=%02X src %04X row %d col %d", z(0x07), b("L1_SRC") + 256 * b("L1_SRC", 1), b("L1_ROW"), z(0x05))
        else
          s = string.format("%s $07=%02X", n, z(0x07))
        end
        log:write(string.format("f%d %s\n", f, s))
        log:flush()
      end
      return d
    end)
  end
end
L1DEL_TAPS = taps
emu.register_frame_done(function()
  f = f + 1
  if f > TO then log:close(); M:exit() end
end)
