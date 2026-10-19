local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local ring, k, f = {}, 0, 0
local function rd(a) return mem:read_u8(a) end
TFP = mem:install_read_tap(S.FlPut, S.FlPut, "fp", function(a, d)
  if a ~= cpu.state["PC"].value then return d end
  local sp = cpu.state["SP"].value & 0xFF
  local ret = rd(0x101 + sp) + 256 * rd(0x102 + sp)
  k = k + 1
  ring[(k % 60) + 1] = string.format("%d f%d R %d X %d B %d V %02X ret %04X X0 %d X1 %d LA %d LB %d T %d K %d Z %d HEAD %d", k, f,
    rd(S.FL_R), rd(S.FL_X), rd(S.FL_B), rd(S.FL_V), ret, rd(S.FL_X0), rd(S.FL_X1), rd(S.FL_LA), rd(S.FL_LB), rd(S.FL_T), rd(S.FL_K), rd(S.FL_Z), rd(S.FL_HEAD))
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f == tonumber(os.getenv("END")) - 1 then
    local o = io.open("flput.log", "w")
    for i = k - 59, k do if i > 0 then o:write(ring[(i % 60) + 1] .. "\n") end end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
