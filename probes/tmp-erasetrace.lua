-- (debug) a companion of p7800-stateplay.lua (SPALSO), or alone: from frame
-- PFROM to PTO, each entry of the box erases (ErP, ErE), their fills (NoFill,
-- NoPat), the fills' clip hook (L1FillF) and level 1's fill (L1Fill), with
-- S_L1, S_ERS, S_NOFILL, L1F_PAT, the fill's box ($05-$09, $06-$08) and the
-- level-1 set's instance count for the buffer, to erasetrace.log (the
-- cutscene guard's ghost: does his box erase reach the set?)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local zp = {}
for l in io.lines(os.getenv("ZPMAP")) do local z, a = l:match("(%x+) (%x+)"); if z then zp[tonumber(z, 16)] = tonumber(a, 16) end end
local FROM = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "999999")
local log = io.open("erasetrace.log", "w")
local f = 0
local taps = {}
local function z(a) return mem:read_u8(zp[a]) end
local function v(n) return sym[n] and mem:read_u8(sym[n]) or -1 end
for _, n in ipairs({"ErP", "ErE", "NoFill", "NoPat", "L1FillF", "L1Fill", "L1Del", "TopFlip"}) do
  local a = sym[n]
  if a then
    taps[#taps + 1] = mem:install_read_tap(a, a, "e" .. n, function(ad, d)
      if f >= FROM and f <= TO and ad == cpu.state["PC"].value then
        log:write(string.format("f%d %-8s $07=%02X S_L1=%02X S_ERS=%02X NOFILL=%02X PAT=%02X box c%d-%d r%d-%d X=%02X\n",
          f, n, z(0x07), v("S_L1"), v("S_ERS"), v("S_NOFILL"), v("L1F_PAT"), z(0x05), z(0x09), z(0x06), z(0x08),
          cpu.state["X"].value))
        if (n == "L1Fill" and v("L1F_PAT") == 0x80 and os.getenv("DUMPI")) or (n == "TopFlip" and os.getenv("DUMPF")) then
          -- (the buffers' instances: shape, its image, row, rows' end, width byte, place)
          for b = 0, 1 do
            local base, cnt = b * 0x30, mem:read_u8(sym.L1_N + b)
            local s = string.format("    buffer %d, %d:", b, cnt)
            for i = 0, cnt - 1 do
              local sha, xa = mem:read_u8(sym.L1_SHA + base + i), mem:read_u8(sym.L1_XA + base + i)
              local y = ((sha & 0x7F) + v("L1_KB")) & 0xFF
              s = s .. string.format(" [%02X%02X r%d-%d w%02X x%d]", mem:read_u8(sym.L1K_SHI + y), mem:read_u8(sym.L1K_SLO + y),
                mem:read_u8(sym.L1K_ROW + y), mem:read_u8(sym.L1K_ROWE + y), mem:read_u8(sym.L1K_W + y), xa)
            end
            log:write(s .. "\n")
          end
        end
        log:flush()
      end
      return d
    end)
  end
end
ET_TAPS = taps
emu.register_frame_done(function() f = f + 1 end)
if os.getenv("ALSO") then dofile(os.getenv("PROBES") .. "/" .. os.getenv("ALSO")) end
