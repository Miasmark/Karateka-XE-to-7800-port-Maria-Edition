-- which blitter called BlitBank (FINDINGS "Akuma as objects"): at each
-- BlitBank entry, the return addresses on the stack (the header read's
-- return into the blitter, then the blitter's caller's) and $03/$04, $05,
-- $06, $0F, $10; each distinct (blitter return, caller) pair once, with a
-- count, to blitkind.log at the end. Runs playkey.lua (its env applies).
-- END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local function zp(x) return mem:read_u8(ZM[x]) end
local function rd(a) return mem:read_u8(a) end
local function ret(sp, k) return rd(0x100 + ((sp + k) & 0xFF)) + 256 * rd(0x100 + ((sp + k + 1) & 0xFF)) end
local seen, f = {}, 0
local FROM = tonumber(os.getenv("FROM") or "0")
T1 = mem:install_read_tap(S.BlitBank, S.BlitBank, "bk1", function(a, d)
  if a ~= cpu.state["PC"].value or f < FROM then return d end
  local sp = cpu.state["SP"].value & 0xFF
  local k = string.format("ret1 %04X ret2 %04X ret3 %04X", ret(sp, 1), ret(sp, 3), ret(sp, 5))
  local e = seen[k]
  if not e then
    e = {n = 0, ex = string.format("src %02X%02X col %d row %d mode %02X shift %d bank %d", zp(4), zp(3), zp(5),
      zp(6), zp(0x0F), zp(0x10), rd(S.S_BANK))}
    seen[k] = e
  end
  e.n = e.n + 1
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    local o = io.open("blitkind.log", "w")
    local ks = {}
    for k in pairs(seen) do ks[#ks + 1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do o:write(string.format("%6d %s  e.g. %s\n", seen[k].n, k, seen[k].ex)) end
    o:close()
    if os.getenv("NOPLAY") then M:exit() end
  end
end)
-- NOPLAY=1: a recording played back (no playkey); FROM: count from this frame
if not os.getenv("NOPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
