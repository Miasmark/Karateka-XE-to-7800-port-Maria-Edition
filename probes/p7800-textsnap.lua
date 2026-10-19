-- the title and the story as shown, for comparing builds (FINDINGS "The
-- title and the opening scroll in bank 0's MARIA copy"): screenshots
--   title-<k>.png: frames after the title's marks (S_TITLEA, S_TITLEB) first
--     reach their final values (both buffers the logo, one the copyright):
--     TFR (comma list, default 5,40);
--   step-<n>.png: SAT frames (default 5) after the story's step counter
--     (S_STORYT) becomes each of STEPS (comma list),
-- to textsnap.log their frames. The attract loop, no keys pressed (K0 off).
-- Runs playkey.lua.
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "4300")
local SAT = tonumber(os.getenv("SAT") or "5")
local steps, tfr = {}, {}
for t in (os.getenv("STEPS") or "5,20,60,100,139,140,141,200,260,300,350,376"):gmatch("%d+") do steps[tonumber(t)] = true end
for t in (os.getenv("TFR") or "5,40"):gmatch("%d+") do tfr[#tfr + 1] = tonumber(t) end
local log = io.open("textsnap.log", "w")
local f, laststep, stepat, tdone, want = 0, -1, {}, nil, {}
local function snap(name)
  M.video:snapshot()
  log:write(string.format("%s frame %d\n", name, f))
  log:flush()
end
emu.register_frame_done(function()
  f = f + 1
  local ta, tb = mem:read_u8(S.S_TITLEA), mem:read_u8(S.S_TITLEB)
  if not tdone and (ta | tb) == 3 and ta ~= 0 and tb ~= 0 then
    tdone = f
    for _, k in ipairs(tfr) do want[f + k] = "title-" .. k end
  end
  local st = mem:read_u8(S.S_STORYT) + 256 * mem:read_u8(S.S_STORYT + 1)
  if mem:read_u8(S.S_STORY) ~= 0 and st ~= laststep then
    laststep = st
    if steps[st] and not stepat[st] then stepat[st] = true; want[f + SAT] = "step-" .. st end
  end
  if want[f] then snap(want[f]) end
  if f >= END then log:close(); M:exit() end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
