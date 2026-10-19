-- the scratch row's bytes the blitters write in floor blits, against FlBlitP's FL_X0-FL_X1:
-- per blit kind, how often the write's column lies at X0, X1, or inside
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local SCR = S.FL_SCR
local cnt = {}
local function k(s) cnt[s] = (cnt[s] or 0) + 1 end
TW = mem:install_write_tap(SCR, SCR + 43, "scr", function(a, d)
  local pc = cpu.state["PC"].value
  if pc < 0x7C00 or pc > 0x7FFF then return end
  local col = a - SCR
  local x0, x1 = mem:read_u8(S.FL_X0), mem:read_u8(S.FL_X1)
  local m = mem:read_u8(S.FL_MIR)
  local z1e = mem:read_u8(ZM1E)
  local w = mem:read_u8(ZM0E)
  local tag = (m == 1 and "M" or "A")
  if col < x0 or col > x1 then k(tag .. " outside") 
  else k(string.format("%s col-$1E %d (w %d)", tag, col - z1e, w)) end
end)
local ZM = {}
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
ZM1E, ZM0E = ZM[0x1E], ZM[0x0E]
emu.register_frame_done(function()
  if manager.machine.time.seconds > 0 and (PLAYKEY_N or 0) == 600 and not DONE then
    DONE = true
    local o = io.open("scrcols.log", "w")
    local ks = {}
    for s, n in pairs(cnt) do ks[#ks + 1] = s end
    table.sort(ks)
    for _, s in ipairs(ks) do o:write(string.format("%8d %s\n", cnt[s], s)) end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
