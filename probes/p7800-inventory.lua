-- the inventory (FINDINGS "The inventory"): every read of ROM ($8000-$BFFF
-- by the bank in, S_BANK; $C000-$FFFF the fixed bank, "F"), classed X (an
-- opcode: the address is the PC), O (an operand: one or two past it) or D
-- (data, MARIA's reads included), under a label for the stretch of the
-- game: "s<$D0>" (the game's scene); scene 1 split by $4C (which structure
-- it draws: "s1g<$4C>"); "s1cut"/"s2cut" for a flip that draws the art
-- bank's door frames or cutscene figures; "text" while the story or title
-- is up. A flip's reads are taken under the label it ends with. From the
-- BIOS's hand-over. To inventory.txt at END: per label and bank, the
-- address runs of each class ("label bank class lo-hi,lo-hi,...").
-- Runs playkey.lua unless NOPLAY (as p7800-stateplay.lua's SPALSO).
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
local END = tonumber(os.getenv("END") or "6000")
local KEEP = S.BlitBankKeep
local CUT = {[0x9600] = true, [0x964A] = true, [0x96CE] = true, [0x971D] = true, [0x9743] = true,
             [0x974B] = true, [0x9EB8] = true, [0x9F8C] = true, [0x9FC4] = true, [0x984F] = true}
local live = false
local flip = {}          -- this flip's reads: key (bank * 65536 + address) -> class bits
local cutflip = false
local acc = {}           -- label -> key -> class bits
local BIT = {X = 1, O = 2, D = 4}
TH = mem:install_write_tap(0x0001, 0x0001, "inv_h", function(a, d)
  if (d & 0x05) == 0x05 then live = true end
end)
TR = mem:install_read_tap(0x8000, 0xFFFF, "inv_r", function(a, d)
  if not live then return d end
  local pc = cpu.state["PC"].value
  local c = (a == pc) and 1 or ((a > pc and a <= pc + 2) and 2 or 4)
  local bank = (a >= 0xC000) and 15 or mem:read_u8(S.S_BANK)
  local k = bank * 65536 + a
  flip[k] = (flip[k] or 0) | c
  if a == KEEP and c == 1 then
    local src = zp(0x04) * 256 + zp(0x03)
    if CUT[src] and mem:read_u8(S.S_BANK) == 6 then cutflip = true end
  end
  return d
end)
local function label()
  if (mem:read_u8(S.S_STORY) | mem:read_u8(S.S_TITLEA) | mem:read_u8(S.S_TITLEB)) ~= 0 then return "text" end
  local d0 = zp(0xD0)
  if cutflip and (d0 == 1 or d0 == 2) then return "s" .. d0 .. "cut" end
  if d0 == 1 then return "s1g" .. zp(0x4C) end
  return "s" .. d0
end
local lastflip = -1
local f = 0
local function close_flip()
  local l = label()
  local t = acc[l]
  if not t then t = {}; acc[l] = t end
  for k, c in pairs(flip) do t[k] = (t[k] or 0) | c end
  flip = {}
  cutflip = false
end
local function dump()
  local o = io.open("inventory.txt", "w")
  for l, t in pairs(acc) do
    local by = {}
    for k, c in pairs(t) do
      local bank, a = k >> 16, k & 0xFFFF
      for _, cls in ipairs({"X", "O", "D"}) do
        if c & BIT[cls] ~= 0 then
          local kk = bank .. " " .. cls
          by[kk] = by[kk] or {}
          table.insert(by[kk], a)
        end
      end
    end
    for kk, list in pairs(by) do
      table.sort(list)
      local runs, lo, prev = {}, nil, nil
      for _, a in ipairs(list) do
        if lo and a == prev + 1 then prev = a
        else
          if lo then runs[#runs + 1] = string.format("%04X-%04X", lo, prev) end
          lo, prev = a, a
        end
      end
      if lo then runs[#runs + 1] = string.format("%04X-%04X", lo, prev) end
      o:write(l .. " " .. kk .. " " .. table.concat(runs, ",") .. "\n")
    end
  end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  local n = PLAYKEY_N or f
  if n ~= lastflip then close_flip(); lastflip = n end
  if f == END then close_flip(); dump() end
end)
if not os.getenv("NOPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
