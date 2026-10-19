-- (debug) playkey.lua (or NOPLAYKEY=1: as p7800-stateplay.lua's companion),
-- plus: at the end of every frame while S_L1 is on, level 1's list pieces'
-- use (L1_SGP against the pieces' starts, the L1SA*/L1SB* symbols, for the buffer L1_SG
-- names): each piece's most bytes used and the most in all a buffer's
-- console-RAM pieces at once, to l1seg.log at the run's end
if not os.getenv("NOPLAYKEY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
if not SYM_ADDR then dofile(os.getenv("PROBES") .. "/p7800-sym.lua") end
local S = SYM_ADDR
local most, tot, fr = {[0] = {}, [8] = {}}, {[0] = 0, [8] = 0}, 0
local size = {[0] = {}, [8] = {}}
RU_LS = emu.add_machine_frame_notifier(function()
  if mem:read_u8(S.S_L1) ~= 1 then return end
  fr = fr + 1
  local sg = mem:read_u8(S.L1_SG)
  if sg ~= 0 and sg ~= 8 then return end
  local t = 0
  for k = 0, 6 do
    local nm = (sg == 0 and "L1SA" or "L1SB") .. k
    local st, en = S[nm], S[nm .. "E"]
    local p = mem:read_u8(S.L1_SGP + 2 * k) + 256 * mem:read_u8(S.L1_SGP + 2 * k + 1)
    local u = p - st
    size[sg][k] = en - st
    if u > (most[sg][k] or 0) then most[sg][k] = u end
    if st < 0x4000 then t = t + u end
  end
  if t > tot[sg] then tot[sg] = t end
end)
RU_LSS = emu.add_machine_stop_notifier(function()
  local o = io.open("l1seg.log", "w")
  o:write(string.format("level-1 frames %d\n", fr))
  for _, sg in ipairs({0, 8}) do
    local u = {}
    for k = 0, 6 do u[#u + 1] = string.format("%d/%d", most[sg][k] or 0, size[sg][k] or 0) end
    o:write(string.format("buffer %s: pieces' most used/size %s; console RAM's most at once %d\n",
      sg == 0 and "A" or "B", table.concat(u, " "), tot[sg]))
  end
  o:close()
end)
