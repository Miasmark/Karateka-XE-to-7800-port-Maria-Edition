-- (debug) playkey.lua, plus: every frame, the shown DLL's entries whose list
-- is in ROM ($8000-$FFFF): each distinct (list address, line) once, with
-- the first frame, $D0 (ZPFILE's map), S_TITLEA/B, S_STORY, the bank in
-- (S_BANK) and the DLL's address, to romlists.log at END - 5
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local S = SYM_ADDR
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPFILE")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local END = tonumber(os.getenv("END") or "300")
local dpp = {[0x2C] = 0, [0x30] = 0}
TRL = mem:install_write_tap(0x2C, 0x30, "rldpp", function(a, d)
  if a == 0x2C or a == 0x30 then dpp[a] = d end
end)
local seen, order, f = {}, {}, 0
RU_RL = emu.add_machine_frame_notifier(function()
  f = f + 1
  if f == END - 5 then
    local o = io.open("romlists.log", "w")
    for _, k in ipairs(order) do o:write(seen[k] .. "\n") end
    o:close()
    return
  end
  local dll = dpp[0x2C] * 256 + dpp[0x30]
  local line = 0
  for e = 0, 90 do
    local b0, hi, lo = mem:read_u8(dll + 3 * e), mem:read_u8(dll + 3 * e + 1), mem:read_u8(dll + 3 * e + 2)
    local a = hi * 256 + lo
    if a >= 0x8000 then
      local k = string.format("%04X@%d", a, line)
      if not seen[k] then
        order[#order + 1] = k
        seen[k] = string.format("list $%04X line %3d h%2d: first frame %d, D0 %02X, title %d/%d story %d, bank %d, DLL $%04X",
          a, line, (b0 & 15) + 1, f, mem:read_u8(ZM[0xD0]), mem:read_u8(S.S_TITLEA), mem:read_u8(S.S_TITLEB),
          mem:read_u8(S.S_STORY), mem:read_u8(S.S_BANK), dll)
      end
    end
    line = line + (b0 & 15) + 1
    if line >= 243 then break end
  end
end)
