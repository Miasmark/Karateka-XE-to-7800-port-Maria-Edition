-- (debug) a companion of p7800-stateplay.lua (SPALSO): every read of RLO-RHI
-- (hex) in flips PFROM to PTO: flip, address, PC (fetches included: an
-- address equal to PC is code run there), each distinct (flip, address, PC)
-- once, to rwatch.log at PTO; MAME exits
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local LO = tonumber(os.getenv("RLO") or "F749", 16)
local HI = tonumber(os.getenv("RHI") or "F787", 16)
local FR = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
RW_SEEN, RW_LIST = {}, {}
RW_TAP = mem:install_read_tap(LO, HI, "rwatch", function(ad, d)
  local n = _G.STATEPLAY_N or 0
  if n >= FR and n <= TO then
    local pc = cpu.state["PC"].value
    local k = string.format("flip %d $%04X pc $%04X", n, ad, pc)
    if not RW_SEEN[k] then RW_SEEN[k] = true; RW_LIST[#RW_LIST + 1] = k end
  end
  return d
end)
emu.register_frame_done(function()
  if (_G.STATEPLAY_N or 0) > TO then
    local o = io.open("rwatch.log", "w")
    for _, k in ipairs(RW_LIST) do o:write(k .. "\n") end
    o:close()
    M:exit()
  end
end)
