-- at frame AT, with the stack as it is, the CPU jumps to JUMP (hex; a game
-- routine the scene has, e.g. its ending), then snapshots at FRAMES (comma
-- list); stops after the last. WITHPLAY=1: playkey.lua drives input (its env
-- applies) until AT. For looking at a screen no recording reaches.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local AT, JUMP = tonumber(os.getenv("AT") or "0"), tonumber(os.getenv("JUMP"), 16)
-- ATFLIP: rather from the scripted player's flip ATFLIP (WITHPLAY=1), so two
-- builds that keep step by flips (not frames) jump at the same moment
local ATFLIP = tonumber(os.getenv("ATFLIP") or "-1")
local want, last = {}, 0
for t in (os.getenv("FRAMES") or ""):gmatch("%d+") do local n = tonumber(t); want[n] = true; if n > last then last = n end end
-- (it waits from AT for a safe moment: the scene page in the window, and
-- neither the vertical blank nor a DLI running; the addresses from SYM)
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local f, done = 0, false
emu.register_frame_done(function()
  f = f + 1
  if f >= AT and (ATFLIP < 0 or (PLAYKEY_N or 0) >= ATFLIP) and not done and mem:read_u8(sym.S_BANK) == mem:read_u8(sym.S_SCENEBANK)
     and mem:read_u8(sym.S_INVBI) == 0 and mem:read_u8(sym.S_INDLI) == 0 and mem:read_u8(sym.S_BUSY) == 0 then
    cpu.state["PC"].value = JUMP
    done = true
    print("jumped at frame " .. f .. " flip " .. (PLAYKEY_N or -1))
  end
  if want[f] then M.video:snapshot() end
  if f >= last then M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
