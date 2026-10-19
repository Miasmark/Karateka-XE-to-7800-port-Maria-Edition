-- (debug) the CPU's instruction fetches from cart RAM ($4000-$7FFF, v1's
-- BankSet RAM): the first LIMIT fetches at new addresses, with the frame,
-- S_BANK, SP and the stack's top bytes (the return addresses), to
-- cartexec.log; a run under run7800.sh (FINDINGS "Code in cart RAM: $7210")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local log = io.open("cartexec.log", "w")
local LIMIT = tonumber(os.getenv("LIMIT") or "40")
local seen, n, fr = {}, 0, 0
local END = tonumber(os.getenv("END") or "6000")
CEX_TAP = mem:install_read_tap(tonumber(os.getenv("CLO") or "16384"), tonumber(os.getenv("CHI") or "32767"), "cex", function(a, d)
  if n < LIMIT and (os.getenv("ANYREAD") or cpu.state["PC"].value == a) and not seen[a .. "/" .. cpu.state["PC"].value] then
    seen[a .. "/" .. cpu.state["PC"].value] = true; n = n + 1
    local sp = cpu.state["SP"].value & 0xFF
    local st = {}
    for k = 1, 8 do st[#st + 1] = string.format("%02X", mem:read_u8(0x100 + ((sp + k) & 0xFF))) end
    log:write(string.format("f%d addr $%04X PC $%04X op %02X bank %02X scene %02X SP %02X stack %s\n", fr, a, cpu.state["PC"].value, d,
      mem:read_u8(S.S_BANK), mem:read_u8(S.G_ZD0), sp, table.concat(st, " ")))
    log:flush()
  end
  return d
end)
emu.register_frame_done(function()
  fr = fr + 1
  if fr >= END then M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
