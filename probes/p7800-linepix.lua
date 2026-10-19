-- the picture MARIA builds, read from memory the way it reads it: at the
-- frame end after flip K (env, playkey's count), the display list list last
-- set (DPPH $2C / DPPL $30), each zone's objects (4- and 5-byte headers,
-- direct and indirect: CHBASE $34, CTRL $3C bit 4 the character width), each
-- line's 160 pixels (160A: a later object over an earlier one's where its
-- pixel is not 0; 160B, the write mode a 5-byte header sets and MARIA keeps
-- till the next one, across objects, lines and zones: two pixels a byte,
-- each its colour and palette), as one character per pixel: '.' for 0, else
-- "0123456789abcdefghijklmnopqrstuv"[palette*4 + value]; to linepix.txt, a
-- line of the list per text line. Compare two builds' with diff. Runs
-- playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local K = tonumber(os.getenv("K") or "300")
local reg = {[0x2C] = 0, [0x30] = 0, [0x34] = 0, [0x3C] = 0}
TREG = mem:install_write_tap(0x2C, 0x3C, "linepix", function(a, d)
  if reg[a] then reg[a] = d end
end)
local CH = "0123456789abcdefghijklmnopqrstuv"
-- a BankSet cart (header bit 13): MARIA reads ROM from the cart's second half
-- (its fixed bank at $C000, its copy of the CPU's bank in the window), which
-- Lua's address space (the CPU's view) doesn't show: read from the file
local maria, mbanks = nil, 0
do
  local fh = io.open(os.getenv("CART") or "", "rb")
  if fh then
    local d = fh:read("a")
    fh:close()
    if #d > 128 and ((d:byte(54) << 8) | d:byte(55)) & 0x2000 ~= 0 then
      local half = (#d - 128) // 2
      maria = d:sub(129 + half)
      mbanks = half // 0x4000
    end
  end
end
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local function rd(a)
  a = a & 0xFFFF
  if maria and a >= 0x8000 then
    local bank = (a >= 0xC000) and (mbanks - 1) or mem:read_u8(SYM_ADDR.S_BANK)
    return maria:byte(bank * 0x4000 + (a & 0x3FFF) + 1)
  end
  return mem:read_u8(a)
end
local done = false
local wm = 0                  -- MARIA's write mode (bit 7 of a 5-byte header)
local function dump()
  local o = io.open("linepix.txt", "w")
  local dll = reg[0x2C] * 256 + reg[0x30]
  local cw = ((reg[0x3C] & 0x10) ~= 0) and 2 or 1
  local cb = reg[0x34]
  local line = 0
  for e = 0, 90 do
    local fl, hi, lo = rd(dll + 3 * e), rd(dll + 3 * e + 1), rd(dll + 3 * e + 2)
    local off = fl & 0x0F
    local dl = hi * 256 + lo
    local hs, q = {}, dl
    for n = 1, 16 do
      local b1 = rd(q + 1)
      if b1 == 0 then break end
      if (b1 & 0x1F) == 0 then hs[#hs + 1] = string.format("[%02X %02X %02X %02X %02X]", rd(q), b1, rd(q + 2), rd(q + 3), rd(q + 4)); q = q + 5
      else hs[#hs + 1] = string.format("[%02X %02X %02X %02X]", rd(q), b1, rd(q + 2), rd(q + 3)); q = q + 4 end
    end
    o:write(string.format("--- z%02d line %d flags %02X lines %d dl %04X %s\n", e, line, fl, off + 1, dl, table.concat(hs, " ")))
    for i = 0, off do
      local ov = off - i
      local px = {}
      for x = 0, 159 do px[x] = 0 end
      local p = dl
      for n = 1, 64 do
        local b0, b1 = rd(p), rd(p + 1)
        if b1 == 0 then break end
        local ind, alo, ahi, pal, w, hp
        if (b1 & 0x1F) == 0 then              -- 5-byte header
          ind = (b1 & 0x20) ~= 0
          alo, ahi = b0, rd(p + 2)
          pal = rd(p + 3) >> 5; w = 32 - (rd(p + 3) & 0x1F); hp = rd(p + 4)
          wm = b1 & 0x80
          p = p + 5
        else
          ind = false
          alo, ahi = b0, rd(p + 2)
          pal = b1 >> 5; w = 32 - (b1 & 0x1F); hp = rd(p + 3)
          p = p + 4
        end
        local bytes = {}
        if ind then
          for k = 0, w - 1 do
            local code = rd((ahi * 256 + alo + k) & 0xFFFF)
            for c = 0, cw - 1 do bytes[#bytes + 1] = rd(((cb + ov) & 0xFF) * 256 + code + c) end
          end
        else
          for k = 0, w - 1 do bytes[#bytes + 1] = rd(((ahi + ov) & 0xFF) * 256 + alo + k) end
        end
        for k, b in ipairs(bytes) do
          if wm ~= 0 then
            for q = 0, 1 do
              local v = (b >> (6 - 2 * q)) & 3
              local pp = (pal & 4) | ((b >> (2 - 2 * q)) & 3)
              local x = (hp + (k - 1) * 2 + q) & 0xFF
              if v ~= 0 and x < 160 then px[x] = pp * 4 + v end
            end
          else
            for q = 0, 3 do
              local v = (b >> (6 - 2 * q)) & 3
              local x = (hp + (k - 1) * 4 + q) & 0xFF
              if v ~= 0 and x < 160 then px[x] = pal * 4 + v end
            end
          end
        end
      end
      local s = {}
      for x = 0, 159 do s[#s + 1] = px[x] == 0 and "." or CH:sub(px[x] + 1, px[x] + 1) end
      o:write(string.format("%3d z%02d %s\n", line, e, table.concat(s)))
      line = line + 1
    end
    if line >= 243 then break end
  end
  o:close()
end
emu.register_frame_done(function()
  if not done and (PLAYKEY_N or 0) >= K then done = true; dump() end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
