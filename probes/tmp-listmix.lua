-- (debug) playkey.lua, plus: every frame while S_L1 is on, the shown DLL's
-- lists, their headers sorted by kind: by the screen part (top: lines
-- 48-112; band: 113-193; low: the rest) and by what the header shows
-- (indirect = tiles; else its data's page: MARIA's ROM $80-$FF, cart RAM
-- $40-$7F, console RAM), with the list ends; the frame with the most bytes
-- in each part and its mix, and the totals, to listmix.log at END - 5 frames
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "300")
local dpp = {[0x2C] = 0, [0x30] = 0}
TLM = mem:install_write_tap(0x2C, 0x30, "lmdpp", function(a, d)
  if a == 0x2C or a == 0x30 then dpp[a] = d end
end)
local function part(line)
  if line >= 48 and line <= 112 then return "top" end
  if line >= 113 and line <= 193 then return "band" end
  return "low"
end
local best = {top = {n = 0}, band = {n = 0}, low = {n = 0}}
local f = 0
local function kind(c1, c3, hi)
  if c1 & 0x1F == 0 and c1 & 0x20 ~= 0 then return "indirect" end
  if hi >= 0x80 then return "rom" end
  if hi >= 0x40 then return "cartram" end
  return "console"
end
RU_LM = emu.add_machine_frame_notifier(function()
  f = f + 1
  if f == END - 5 then
    local o = io.open("listmix.log", "w")
    for _, p in ipairs({"top", "band", "low"}) do
      local b = best[p]
      local t = {}
      for k, v in pairs(b.mix or {}) do t[#t + 1] = string.format("%s %d", k, v) end
      table.sort(t)
      o:write(string.format("%s: most %d bytes (frame %d): %s\n", p, b.n, b.f or 0, table.concat(t, ", ")))
    end
    o:close()
  end
  if mem:read_u8(S.S_L1) ~= 1 then return end
  local dll = dpp[0x2C] * 256 + dpp[0x30]
  local line = 0
  local tot = {top = 0, band = 0, low = 0}
  local mix = {top = {}, band = {}, low = {}}
  local seen = {}
  for e = 0, 90 do
    local b0, lhi, llo = mem:read_u8(dll + 3 * e), mem:read_u8(dll + 3 * e + 1), mem:read_u8(dll + 3 * e + 2)
    local a = lhi * 256 + llo
    local p = part(line)
    if not seen[a] then
      seen[a] = true
      local n = 0
      for k = 1, 40 do
        local c1 = mem:read_u8(a + n + 1)
        local kd, sz
        if c1 & 0x1F == 0 then
          if c1 == 0 then kd, sz = "end", 2
          else kd, sz = kind(c1, 0, mem:read_u8(a + n + 2)), 5
            if c1 & 0x20 ~= 0 then kd = "indirect" end
            kd = kd .. "5"
          end
        else
          kd, sz = kind(c1, 0, mem:read_u8(a + n + 2)) .. "4", 4
        end
        mix[p][kd] = (mix[p][kd] or 0) + sz
        tot[p] = tot[p] + sz
        n = n + sz
        if kd == "end" then break end
      end
    end
    line = line + (b0 & 15) + 1
    if line >= 243 then break end           -- (DLL_LINES: MARIA reads no further)
  end
  for _, p in ipairs({"top", "band", "low"}) do
    if tot[p] > best[p].n then best[p] = {n = tot[p], f = f, mix = mix[p]} end
  end
end)
