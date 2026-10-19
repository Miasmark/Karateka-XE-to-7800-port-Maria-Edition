-- S_STORY, S_TITLEA, S_TITLEB, S_OBLANK and FL draws skipped, logged when they change (with the flip)
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local o = io.open("flflags.log", "w")
local last = ""
emu.register_frame_done(function()
  local s = string.format("story %02X titleA %02X titleB %02X oblank %02X", mem:read_u8(S.S_STORY), mem:read_u8(S.S_TITLEA), mem:read_u8(S.S_TITLEB), mem:read_u8(S.S_OBLANK))
  if s ~= last then o:write(string.format("flip %s: %s\n", tostring(PLAYKEY_N), s)); o:flush(); last = s end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
