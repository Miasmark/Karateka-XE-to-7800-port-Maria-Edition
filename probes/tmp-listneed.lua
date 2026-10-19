-- (debug) playkey.lua, plus: every frame, the shown DLL's lists (each list
-- once, to its end), their bytes by scene ($D0 through ZPFILE's map), by the
-- screen's part (top: lines 48-112, band: 113-193, else other) and by where
-- they are (console RAM, cart RAM, ROM): the most in one frame, and the cart
-- RAM ones' address ranges, to listneed.log at END - 5 frames
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPFILE")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local END = tonumber(os.getenv("END") or "300")
local dpp = {[0x2C] = 0, [0x30] = 0}
TLN = mem:install_write_tap(0x2C, 0x30, "lndpp", function(a, d)
  if a == 0x2C or a == 0x30 then dpp[a] = d end
end)
local function bytes(a)
  local n = 0
  for k = 1, 40 do
    local c1 = mem:read_u8(a + n + 1)
    if c1 & 0x1F == 0 then
      if c1 == 0 then return n + 2 end
      n = n + 5
    else
      n = n + 4
    end
  end
  return n
end
local most, rng, f = {}, {}, 0
RU_LN = emu.add_machine_frame_notifier(function()
  f = f + 1
  if f == END - 5 then
    local o = io.open("listneed.log", "w")
    local sc = {}
    for s in pairs(most) do sc[#sc + 1] = s end
    table.sort(sc)
    for _, s in ipairs(sc) do
      local t = {}
      for k, v in pairs(most[s]) do t[#t + 1] = string.format("%s %d", k, v) end
      table.sort(t)
      o:write(string.format("scene %d: %s\n", s, table.concat(t, ", ")))
      local r = {}
      for k in pairs(rng[s]) do r[#r + 1] = k end
      table.sort(r)
      o:write("  cart lists at " .. table.concat(r, " ") .. "\n")
    end
    o:close()
  end
  local s = mem:read_u8(ZM[0xD0])
  most[s] = most[s] or {}
  rng[s] = rng[s] or {}
  local dll = dpp[0x2C] * 256 + dpp[0x30]
  local line, seen, tot = 0, {}, {}
  for e = 0, 90 do
    local b0, hi, lo = mem:read_u8(dll + 3 * e), mem:read_u8(dll + 3 * e + 1), mem:read_u8(dll + 3 * e + 2)
    local a = hi * 256 + lo
    if not seen[a] then
      seen[a] = true
      local part = (line >= 48 and line <= 112) and "top" or ((line >= 113 and line <= 193) and "band" or "other")
      local where = a < 0x4000 and "console" or (a < 0x8000 and "cart" or "rom")
      local k = part .. "/" .. where
      tot[k] = (tot[k] or 0) + bytes(a)
      if where ~= "console" then rng[s][string.format("%s%04X", where == "rom" and "R" or "", a & 0xFFF0)] = true end
    end
    line = line + (b0 & 15) + 1
    if line >= 243 then break end
  end
  for k, v in pairs(tot) do
    if v > (most[s][k] or 0) then most[s][k] = v end
  end
end)
