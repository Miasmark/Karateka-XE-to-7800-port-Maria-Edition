-- the top rows' zone list slots in use (FINDINGS "The fighters as objects:
-- step 1"): per pass (a display-list build, BuildDllF, or a refresh at a
-- flip, TopRefresh) how many slots TopEmit
-- filled (TopEmitEnd, in the top bank), and the most bytes one held (S_EW
-- there: the objects' headers, before the end). To topslots.log at the end:
-- the histograms. Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local f, cur, maxb = 0, 0, 0
local slots, bytes, index = {}, {}, {}
local function pc() return cpu.state["PC"].value end
local function pass(a, d)
  if a == pc() and (a < 0x8000 or mem:read_u8(S.S_BANK) == 5) then
    if cur > 0 then slots[cur] = (slots[cur] or 0) + 1 end
    cur = 0
  end
  return d end
T1 = mem:install_read_tap(S.BuildDllF, S.BuildDllF, "ts1", pass)
T3 = mem:install_read_tap(S.TopRefresh, S.TopRefresh, "ts3", pass)
T2 = mem:install_read_tap(S.TopEmitEnd, S.TopEmitEnd, "ts2", function(a, d)
  if a == pc() and mem:read_u8(S.S_BANK) == 5 then
    cur = cur + 1
    local b = mem:read_u8(S.S_EW)
    bytes[b] = (bytes[b] or 0) + 1
    local slot = mem:read_u8(S.S_TDLP) + 256 * mem:read_u8(S.S_TDLP + 1)   -- (this slot, before TopNextSlot)
    for _, base in ipairs({S.TOPDL_A, S.TOPDL_B}) do
      local off = slot - base
      if off >= 0 and off < 0x400 then
        local idx = (off >> 8) * 3 + ((off & 0xFF) - 0x00) // 0x50
        index[idx] = (index[idx] or 0) + 1
      end
    end
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    local o = io.open("topslots.log", "w")
    o:write("slots a build:")
    for k = 0, 40 do if slots[k] then o:write(string.format(" %d:%d", k, slots[k])) end end
    o:write("\nbytes in a slot:")
    for k = 0, 255 do if bytes[k] then o:write(string.format(" %d:%d", k, bytes[k])) end end
    o:write("\nslot indexes used:")
    for k = 0, 40 do if index[k] then o:write(string.format(" %d:%d", k, index[k])) end end
    o:write("\n")
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
