-- (debug) cart RAM after each scene's first load (FINDINGS "The ROM by
-- scene: step 1"): at the end of the first frame whose list is not the blank
-- one after a load (BLANK_DLL), $4000-$7FFF to loadcap_<scene>.bin (the
-- game's G_ZD0), once a scene. For probes/loadcmp.py, against the build's
-- <cart>.loadimg. The no-rules MAME (cart RAM read from Lua). Runs
-- playkey.lua (not under port/replay.sh).
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local reg = {[0x2C] = 0, [0x30] = 0}
local wasblank, done = false, {}
TREG = mem:install_write_tap(0x2C, 0x30, "lc_reg", function(a, d) if reg[a] then reg[a] = d end end)
emu.register_frame_done(function()
  local blank = reg[0x2C] * 256 + reg[0x30] == S.BLANK_DLL
  if wasblank and not blank then
    local sc = mem:read_u8(S.G_ZD0)
    if not done[sc] then
      done[sc] = true
      local t = {}
      for a = 0x4000, 0x7FFF do t[#t + 1] = string.char(mem:read_u8(a)) end
      local o = io.open(string.format("loadcap_%d.bin", sc), "wb")
      o:write(table.concat(t))
      o:close()
    end
  end
  wasblank = blank
end)
if not os.getenv("PLAYBACK") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
