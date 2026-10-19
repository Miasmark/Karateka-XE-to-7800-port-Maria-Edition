-- the fighters' runtime cost (FINDINGS "The fighters as objects: step 3"),
-- in scanlines (263 a frame, 113.5 CPU cycles each, less MARIA's DMA): each
-- flip's copy (FtEmit's entry to BandRefresh's) and list refresh
-- (BandRefresh to BandRefDone), and the front-box recorder's calls a flip
-- (FgRec, FgCol), and bank 15's drawing of a fighter (FRec to FtEndDone).
-- To fttime.log at the end: averages, the 95th percentile and
-- the most. Runs playkey.lua (its env applies). END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "6000")
local f, t0, t1 = 0, nil, nil
local copy, refresh, fg, fgn, draw, td = {}, {}, {}, 0, {}, nil
local function now() return M.time:as_double() * 59.92 * 263 end
local function pc() return cpu.state["PC"].value end
local function bank5() return mem:read_u8(S.S_BANK) == 5 end
T1 = mem:install_read_tap(S.FtEmit, S.FtEmit, "tt1", function(a, d)
  if a == pc() and bank5() then t0 = now() end
  return d end)
T2 = mem:install_read_tap(S.BandRefresh, S.BandRefresh, "tt2", function(a, d)
  if a == pc() and bank5() and t0 then t1 = now(); copy[#copy + 1] = t1 - t0 end
  return d end)
T3 = mem:install_read_tap(S.BandRefDone, S.BandRefDone, "tt3", function(a, d)
  if a == pc() and bank5() and t1 then
    refresh[#refresh + 1] = now() - t1; t1 = nil; t0 = nil
    fg[#fg + 1] = fgn; fgn = 0
  end
  return d end)
T5 = mem:install_read_tap(S.FRec, S.FRec, "tt5", function(a, d)
  if a == pc() then td = now() end
  return d end)
T6 = mem:install_read_tap(S.FtEndDone, S.FtEndDone, "tt6", function(a, d)
  if a == pc() and td then draw[#draw + 1] = now() - td; td = nil end
  return d end)
T4 = mem:install_read_tap(S.FgRec, S.FgRec, "tt4", function(a, d)
  if a == pc() then fgn = fgn + 1 end
  return d end)
local function summary(name, t)
  table.sort(t)
  if #t == 0 then return name .. ": none\n" end
  local sum = 0
  for _, v in ipairs(t) do sum = sum + v end
  return string.format("%s: %d, average %.1f, 95%% %.1f, most %.1f\n", name, #t, sum / #t, t[math.floor(#t * 0.95) + 1] or t[#t], t[#t])
end
emu.register_frame_done(function()
  f = f + 1
  if f == END - 1 then
    local o = io.open("fttime.log", "w")
    o:write(summary("copy (scanlines)", copy))
    o:write(summary("list refresh (scanlines)", refresh))
    o:write(summary("RowBase calls a flip", fg))
    o:write(summary("a fighter's drawing by bank 15 (scanlines; its lower-body mask, drawn earlier, not in it)", draw))
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
