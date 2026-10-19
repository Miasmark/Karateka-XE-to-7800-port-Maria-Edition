-- the display's list footprint (FINDINGS "A 144K cart: the fit"): each frame,
-- the DLL last set is walked as MARIA reads it; counted: DLL entries, list
-- bytes (headers and each list's 2-byte end, every list once), and objects
-- by where their data is: cart RAM ($4000-$7FFF: the bitmap, slices, top
-- pieces), console RAM, ROM; and indirect. Not while the story or title
-- (all objects) is up (TEXT=1: only then). The worst frame and the mean, to
-- listsize.log at END. Runs playkey.lua.
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local END = tonumber(os.getenv("END") or "6000")
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local function text_up() return (mem:read_u8(S.S_STORY) | mem:read_u8(S.S_TITLEA) | mem:read_u8(S.S_TITLEB) | mem:read_u8(S.S_OBLANK)) ~= 0 end
local reg = {[0x2C] = 0, [0x30] = 0}
TREG = mem:install_write_tap(0x2C, 0x30, "ls_reg", function(a, d) if reg[a] then reg[a] = d end end)
local function rd(a) return mem:read_u8(a & 0xFFFF) end
local f, n = 0, 0
local sum = {}
local worst = {bytes = 0}
local keys = {"entries", "bytes", "lists", "cart", "console", "rom", "indirect"}
for _, k in ipairs(keys) do sum[k] = 0 end
local function walk()
  local dll = reg[0x2C] * 256 + reg[0x30]
  if dll == 0 then return nil end
  local c = {}
  for _, k in ipairs(keys) do c[k] = 0 end
  local seen = {}
  local line = 0
  for e = 0, 100 do
    local p = dll + 3 * e
    local fl, hi, lo = rd(p), rd(p + 1), rd(p + 2)
    c.entries = c.entries + 1
    local dl = hi * 256 + lo
    if not seen[dl] then
      seen[dl] = true
      c.lists = c.lists + 1
      local q = dl
      for k = 1, 64 do
        local b1 = rd(q + 1)
        if b1 == 0 then c.bytes = c.bytes + 2; break end
        local ahi, size
        if (b1 & 0x1F) == 0 then
          ahi = rd(q + 2); size = 5
          if (b1 & 0x20) ~= 0 then c.indirect = c.indirect + 1 end
        else
          ahi = rd(q + 2); size = 4
        end
        c.bytes = c.bytes + size
        if ahi >= 0x40 and ahi < 0x80 then c.cart = c.cart + 1
        elseif ahi >= 0x18 and ahi < 0x28 then c.console = c.console + 1
        else c.rom = c.rom + 1 end
        q = q + size
      end
    end
    line = line + (fl & 0x0F) + 1
    if line >= 243 then break end
  end
  return c
end
emu.register_frame_done(function()
  f = f + 1
  local c = (text_up() == (os.getenv("TEXT") ~= nil)) and walk() or nil
  if c and c.entries > 3 then
    n = n + 1
    for _, k in ipairs(keys) do sum[k] = sum[k] + c[k] end
    if c.bytes > worst.bytes then worst = c; worst.frame = f; worst.flip = PLAYKEY_N end
  end
  if f == END then
    local o = io.open("listsize.log", "w")
    o:write(string.format("frames %d\n", n))
    for _, k in ipairs(keys) do
      o:write(string.format("%-9s mean %7.1f  worst-frame %d\n", k, sum[k] / math.max(n, 1), worst[k] or 0))
    end
    o:write(string.format("worst frame %s flip %s\n", tostring(worst.frame), tostring(worst.flip)))
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
