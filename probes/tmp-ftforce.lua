-- (alongside p7800-stateplay.lua, SPALSO) at flip FORCEF's emit (FtEmit's
-- entry, buffer A): the old build's records from its flip 2400 written in
-- (the player, Akuma's six blits, the hit star), so both builds draw the same
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = SYM_ADDR
local F = tonumber(os.getenv("FORCEF") or "2400")
local done = false
local blits = {
  {0xA097, 4, 23, 103, 0, 0xE0}, {0xA46F, 4, 23, 103, 0, 0xC0}, {0xA143, 4, 22, 84, 0, 0xE0},
  {0xAC51, 4, 22, 84, 0, 0xC0}, {0xA0D1, 4, 25, 88, 0, 0xE0}, {0xA5FA, 4, 25, 88, 0, 0xC0}}
TFF = mem:install_read_tap(S.FtEmit, S.FtEmit, "ftforce", function(a, d)
  if done or cpu.state["PC"].value ~= S.FtEmit or mem:read_u8(S.S_BANK) ~= 5 then return d end
  if (_G.STATEPLAY_N or 0) ~= F or mem:read_u8(S.S_SLOT) ~= 0 then return d end
  done = true
  local function w(x, v) mem:write_u8(x, v) end
  for i, v in ipairs({2, 24, 6, 13, 0, 7, 0}) do
    w(({S.FR_V, S.FR_20, S.FR_21, S.FR_22, S.FR_50, S.FR_3E, S.FR_36})[i], v)
  end
  w(S.FR_V + 1, 0)
  w(S.FT_SEEN, 1); w(S.FT_DIRTY, 1)
  w(S.SR_V, 2); w(S.SR_IMG, 0); w(S.SR_ROW, 79); w(S.SR_COL, 16); w(S.SR_SUB, 0)
  w(S.AK_V, 2); w(S.AK_N, #blits)
  for k, bl in ipairs(blits) do
    local i = k - 1
    w(S.AK_LO + i, bl[1] & 0xFF); w(S.AK_HI + i, bl[1] >> 8); w(S.AK_BK + i, bl[2]); w(S.AK_COL + i, bl[3])
    w(S.AK_ROW + i, bl[4]); w(S.AK_SH + i, bl[5]); w(S.AK_FL + i, bl[6])
  end
  print("forced at flip " .. F)
  return d
end)
