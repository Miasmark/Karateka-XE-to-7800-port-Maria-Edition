-- the port's draws around the scripted player's flip AT (FINDINGS "The
-- fighters as objects: step 3"), flips AT-2 to AT: each fighter record
-- (FRec), each fighter's end (FtEndDone) and each draw (RowBase's entry,
-- FgRec): the buffer $07, rows ($06 - 35, $0D), a blit's columns ($1E, $0E)
-- and a fill's ($05-$09), the drawing routine's return (the blit's caller,
-- from the stack) and the front boxes' state (FT_SEEN, FT_IN). To
-- drawlog.log. Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local AT = tonumber(os.getenv("AT") or "366")
local o = io.open("drawlog.log", "w")
local function b(a) return mem:read_u8(a) end
local FROM = tonumber(os.getenv("FROM") or AT - 2)   -- (FROM: an earlier first flip)
local function on() local n = PLAYKEY_N or 0; return n >= FROM and n <= AT end
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local function zp(x) return b(ZM[x]) end
local function ret(off)
  local sp = cpu.state["SP"].value & 0xFF
  return b(0x100 + ((sp + off) & 0xFF)) + 256 * b(0x100 + ((sp + off + 1) & 0xFF))
end
T1 = mem:install_read_tap(S.FRec, S.FRec, "dl1", function(a, d)
  if a == cpu.state["PC"].value and on() then
    o:write(string.format("flip %d  FRec $07=%02X $20=%d $21=%d $22=%d $2C=%02X\n", PLAYKEY_N, zp(7), zp(0x20), zp(0x21), zp(0x22), zp(0x2C)))
  end
  return d end)
T2 = mem:install_read_tap(S.FtEndDone, S.FtEndDone, "dl2", function(a, d)
  if a == cpu.state["PC"].value and on() then o:write(string.format("flip %d  fighter done\n", PLAYKEY_N)) end
  return d end)
T3 = mem:install_read_tap(S.FgRec, S.FgRec, "dl3", function(a, d)
  if a == cpu.state["PC"].value and on() then
    local row = (zp(6) - 35) & 0xFF
    o:write(string.format("flip %d  draw $07=%02X rows %d+%d  blit cols %d+%d  fill cols %d-%d  caller %04X %04X  seen %d %d in %d\n",
      PLAYKEY_N, zp(7), row, zp(0x0D), zp(0x1E), zp(0x0E), zp(5), zp(9), ret(5) - 2, ret(7) - 2,
      b(S.FT_SEEN), b(S.FT_SEEN + 1), b(S.FT_IN)))
  end
  return d end)
emu.register_frame_done(function() if (PLAYKEY_N or 0) > AT then o:flush() end end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
