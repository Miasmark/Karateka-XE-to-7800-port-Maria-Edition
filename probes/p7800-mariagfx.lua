-- the graphics MARIA reads (FINDINGS "BankSet step 1: the graphics MARIA
-- reads"): each frame the DLL last set is walked as MARIA reads it; every
-- graphics byte fetched (direct objects' bytes; indirect maps and
-- characters at CHBASE) is marked, by page; text screens (story, title)
-- apart. To mariagfx.log at END: "play|text page bytes". Runs playkey.lua.
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local reg = {[0x2C] = 0, [0x30] = 0, [0x34] = 0}
TREG = mem:install_write_tap(0x2C, 0x34, "mg_reg", function(a, d) if reg[a] then reg[a] = d end end)
local function rd(a) return mem:read_u8(a & 0xFFFF) end
local seen = {play = {}, text = {}}
local f = 0
local function walk(t)
  local dll = reg[0x2C] * 256 + reg[0x30]
  if dll == 0 then return end
  local cb = reg[0x34]
  local line = 0
  for e = 0, 100 do
    local p = dll + 3 * e
    local fl, hi, lo = rd(p), rd(p + 1), rd(p + 2)
    local off = fl & 0x0F
    local dl = hi * 256 + lo
    for i = 0, off do
      local ov = off - i
      local q = dl
      for n = 1, 64 do
        local b1 = rd(q + 1)
        if b1 == 0 then break end
        local ind, alo, ahi, w
        if (b1 & 0x1F) == 0 then
          ind = (b1 & 0x20) ~= 0; alo, ahi = rd(q), rd(q + 2); w = 32 - (rd(q + 3) & 0x1F); q = q + 5
        else
          ind = false; alo, ahi = rd(q), rd(q + 2); w = 32 - (b1 & 0x1F); q = q + 4
        end
        for k = 0, w - 1 do
          if ind then
            local m = (ahi * 256 + alo + k) & 0xFFFF
            local c = rd(m)
            t[((cb + ov) & 0xFF) * 256 + c] = true
          else
            t[(((ahi + ov) & 0xFF) * 256 + alo + k) & 0xFFFF] = true
          end
        end
      end
      line = line + 1
    end
    if line >= 243 then break end
  end
end
emu.register_frame_done(function()
  f = f + 1
  local text = (mem:read_u8(S.S_STORY) | mem:read_u8(S.S_TITLEA) | mem:read_u8(S.S_TITLEB) | mem:read_u8(S.S_OBLANK)) ~= 0
  walk(text and seen.text or seen.play)
  if f == END then
    local o = io.open("mariagfx.log", "w")
    for k, t in pairs(seen) do
      local pg = {}
      for a in pairs(t) do pg[a >> 8] = (pg[a >> 8] or 0) + 1 end
      for p, n in pairs(pg) do o:write(string.format("%s %02X %d\n", k, p, n)) end
    end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
