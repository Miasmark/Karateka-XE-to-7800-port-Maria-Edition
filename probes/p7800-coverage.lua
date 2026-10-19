-- what the code reads (FINDINGS "Coverage: common and bank 15"): every
-- address read (instruction fetches and data alike) in the scene pages'
-- common code ($96E8-$9FFF, with a scene page in: S_BANK 0-4) and in the
-- fixed bank ($C000-$FFFF), from the BIOS's hand-over, as two bitmaps
-- to coverage.bin at END (the common's 2,328 bytes, then the fixed bank's
-- 16,384: 1 read). Runs
-- playkey.lua (its env applies) unless NOPLAY; alongside p7800-stateplay.lua
-- as its SPALSO with NOPLAY=1.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
-- counted from the BIOS's hand-over (its write to INPTCTRL $0001 that
-- locks with the BIOS out: bits 0 and 2), since the BIOS reads the whole
-- cartridge for its signature check first; FROM: a later frame instead
local FROM = tonumber(os.getenv("FROM") or "0")
local f = 0
local on = false
TCV0 = mem:install_write_tap(0x0001, 0x0001, "cv0", function(a, d)
  if (d & 0x05) == 0x05 then on = true end
end)
local SB = S.S_BANK
local com, fix = {}, {}
for i = 0, 0x9FFF - 0x96E8 do com[i] = 0 end
for i = 0, 0x3FFF do fix[i] = 0 end
TCV1 = mem:install_read_tap(0x96E8, 0x9FFF, "cv1", function(a, d)
  if not on or f < FROM then return d end
  local b = mem:read_u8(SB)
  if b <= 4 then com[a - 0x96E8] = 1 end
  return d end)
TCV2 = mem:install_read_tap(0xC000, 0xFFFF, "cv2", function(a, d)
  if on and f >= FROM then fix[a - 0xC000] = 1 end
  return d end)
CVFD = emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    local o = io.open("coverage.bin", "wb")
    local t = {}
    for i = 0, 0x9FFF - 0x96E8 do t[#t + 1] = string.char(com[i]) end
    for i = 0, 0x3FFF do t[#t + 1] = string.char(fix[i]) end
    o:write(table.concat(t))
    o:close()
    if os.getenv("NOPLAY") then M:exit() end
  end
end)
if not os.getenv("NOPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
