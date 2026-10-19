-- (debug) BlitBank's entries: counted by FT_IN and S_GLYIN, and by the
-- image's high byte ($04), to bbcount.log at END. Runs playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local f, c = 0, {}
TBB = mem:install_read_tap(S.BlitBank, S.BlitBank, "bb", function(a, d)
  if a ~= cpu.state["PC"].value then return d end
  local k = string.format("FT_IN=%d GLY=%d src_hi=%02X", mem:read_u8(S.FT_IN), mem:read_u8(S.S_GLYIN), mem:read_u8(S.G_Z04))
  c[k] = (c[k] or 0) + 1
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f % 500 == 0 or f == END then
    local o = io.open("bbcount.log", "w")
    for k, v in pairs(c) do o:write(k .. " " .. v .. "\n") end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
