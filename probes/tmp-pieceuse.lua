-- (debug) the display lists' pieces' use: at each frame's end (the
-- allocators not mid-update), each allocator's row (L1_SG: the band's,
-- TP_SG: the top's; the scene's group and the buffer) and the bytes its
-- pieces hold then (each piece's next byte less its start: the symbol
-- file's L1S<row letter><k>, TPS<row letter><k>), their sum; the largest
-- sum each row reached, to pieceuse.log at each 1000th frame and END:
-- "kind row sum (piece used/size ...)". Runs playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local LET = {[0x00] = "A", [0x08] = "B", [0x10] = "C", [0x18] = "D", [0x20] = "E", [0x28] = "F"}
local best, detail = {}, {}
local function look(kind, pre, base, rowsym)
  local row = mem:read_u8(rowsym)
  local let = LET[row]
  if not let then return end
  local sum, parts = 0, {}
  for k = 0, 6 do
    local lo, hi = S[pre .. let .. k], S[pre .. let .. k .. "E"]
    if lo and hi and hi > lo then
      local v = mem:read_u8(base + 2 * k) + 256 * mem:read_u8(base + 2 * k + 1)
      if v >= lo and v <= hi then
        sum = sum + (v - lo)
        parts[#parts + 1] = string.format("%d/%d", v - lo, hi - lo)
      end
    end
  end
  local key = string.format("%s %02X", kind, row)
  if sum > (best[key] or -1) then best[key] = sum; detail[key] = table.concat(parts, " ") end
end
local f = 0
local function dump()
  local o = io.open("pieceuse.log", "w")
  local ks = {}
  for k in pairs(best) do ks[#ks + 1] = k end
  table.sort(ks)
  for _, k in ipairs(ks) do o:write(string.format("%s %d (%s)\n", k, best[k], detail[k])) end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  look("band", "L1S", S.L1_SGP, S.L1_SG)
  look("top", "TPS", S.TP_SGP, S.TP_SG)
  if f % 1000 == 0 or f == END then dump() end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
