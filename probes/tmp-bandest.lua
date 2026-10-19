-- (debug) the band lists' allocation (BandWL1): at BandWL1F (a piece found
-- for a list) its estimate S_FL0; at BandWEnd the list's real size (Y + 2);
-- at BandWL1X (no piece with room: objects dropped, or the empty list), in
-- play only (not under the blank list, nor with the title's or story's
-- text up), a count and, the first six, the frame, the allocator's row
-- (L1_SG), the estimate and the pieces' next bytes (L1_SGP). Per run: the
-- largest estimate and the largest estimate less real size. To
-- bandest.log at each 1000th frame. Runs playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local f, est = 0, nil
local maxest, maxover, drops, lists = 0, 0, 0, 0
local dropf = {}
local function r(a) return mem:read_u8(a) end
local reg = {[0x2C] = 0, [0x30] = 0}
TREG = mem:install_write_tap(0x2C, 0x30, "be_reg", function(a, d) if reg[a] then reg[a] = d end end)
TF = mem:install_read_tap(S.BandWL1F, S.BandWL1F, "be1", function(a, d)
  if a ~= cpu.state["PC"].value then return d end
  est = r(S.S_FL0)
  if est > maxest then maxest = est end
  return d
end)
TX = mem:install_read_tap(S.BandWL1X, S.BandWL1X, "be2", function(a, d)
  if a ~= cpu.state["PC"].value then return d end
  if reg[0x2C] * 256 + reg[0x30] == S.BLANK_DLL or r(S.S_STORY) ~= 0 or r(S.S_TITLEA) ~= 0
     or r(S.S_TITLEB) ~= 0 then return d end
  drops = drops + 1
  if #dropf < 6 then
    local t = {}
    for k = 0, 6 do t[#t + 1] = string.format("%02X%02X", r(S.L1_SGP + 2 * k + 1), r(S.L1_SGP + 2 * k)) end
    dropf[#dropf + 1] = string.format("f%d row %02X est %d ptrs %s", f, r(S.L1_SG), r(S.S_FL0), table.concat(t, " "))
  end
  return d
end)
TE = mem:install_read_tap(S.BandWEnd, S.BandWEnd, "be3", function(a, d)
  if a ~= cpu.state["PC"].value or est == nil then return d end
  local real = cpu.state["Y"].value + 2
  lists = lists + 1
  if est - real > maxover then maxover = est - real end
  est = nil
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  if f % 1000 == 0 then
    local o = io.open("bandest.log", "w")
    o:write(string.format("lists %d, largest estimate %d, largest estimate less real %d, drops in play %d\n",
      lists, maxest, maxover, drops))
    for _, s in ipairs(dropf) do o:write(s .. "\n") end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
