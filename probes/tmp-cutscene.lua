-- per flip from FROM to TO: $D0, S_SCENEBANK, and the images blitted (bank, src) with BlitBank's kind; to cutscene.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local function zp(x) return mem:read_u8(ZM[x]) end
local FROM, TO = tonumber(os.getenv("FROM") or "400"), tonumber(os.getenv("TO") or "560")
local o = io.open("cutscene.log", "w")
local cur, imgs = -1, {}
T1 = mem:install_read_tap(S.BlitBankKeep, S.BlitBankKeep, "cs", function(a, d)
  if a ~= cpu.state["PC"].value then return d end
  local n = PLAYKEY_N or 0
  if n < FROM or n > TO then return d end
  local src = zp(0x04) * 256 + zp(0x03)
  imgs[string.format("b%d:%04X", mem:read_u8(S.S_BANK), src)] = true
  return d
end)
emu.register_frame_done(function()
  local n = PLAYKEY_N or 0
  if n ~= cur then
    if cur >= FROM and cur <= TO then
      local l = {}
      for k in pairs(imgs) do l[#l + 1] = k end
      table.sort(l)
      o:write(string.format("flip %d D0 %02X scenebank %d: %s\n", cur, zp(0xD0), mem:read_u8(S.S_SCENEBANK), table.concat(l, " ")))
      o:flush()
    end
    cur, imgs = n, {}
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
