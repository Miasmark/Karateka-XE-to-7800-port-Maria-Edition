-- (debug) the title's and story's frames: from frame FROM to TO, the values
-- written to CTRL ($3C) and CHBASE ($34) and to the bank select (S_BANK's
-- writes), counted, with S_STORY, S_TITLEA/B, S_L1, S_PCTRL at each 100th
-- frame, to storydbg.log. Runs playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM, TO = tonumber(os.getenv("FROM") or "1500"), tonumber(os.getenv("TO") or "2500")
local f, c = 0, {}
local function k(s) c[s] = (c[s] or 0) + 1 end
TC = mem:install_write_tap(0x3C, 0x3C, "sd1", function(a, d) if f >= FROM and f <= TO then k(string.format("CTRL=%02X", d)) end end)
TB = mem:install_write_tap(S.S_BANK, S.S_BANK, "sd2", function(a, d) if f >= FROM and f <= TO then k(string.format("bank=%d", d)) end end)
local o = io.open("storydbg.log", "w")
emu.register_frame_done(function()
  f = f + 1
  if f >= FROM and f <= TO and f % 100 == 0 then
    local r = function(x) return mem:read_u8(x) end
    o:write(string.format("f%d STORY=%d TA=%d TB=%d L1=%d PCTRL=%02X\n", f, r(S.S_STORY), r(S.S_TITLEA), r(S.S_TITLEB), r(S.S_L1), r(S.S_PCTRL)))
  end
  if f == TO then
    local ks = {}
    for x in pairs(c) do ks[#ks + 1] = x end
    table.sort(ks)
    for _, x in ipairs(ks) do o:write(x .. " " .. c[x] .. "\n") end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
