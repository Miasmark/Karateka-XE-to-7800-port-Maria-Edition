-- when named routines run: each symbol in NAMES (comma list, from SYM) is
-- logged with its frame each time its first byte is fetched as an opcode
-- (for banked code, only while BANK, if given as NAME@bank, is in: S_BANK),
-- to pctimes.log, at most 40 times a name. Runs p7800-jumpto.lua when
-- JUMP is set (its env applies), else playkey.lua. END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local f, out, n = 0, io.open("pctimes.log", "w"), {}
for item in (os.getenv("NAMES") or ""):gmatch("[^,]+") do
  local name, bank = item:match("([^@]+)@?(%d*)")
  local a = S[name]
  if not a then out:write("no symbol " .. name .. "\n") else
    bank = tonumber(bank)
    n[name] = 0
    _G["T_" .. name] = mem:install_read_tap(a, a, "pt" .. name, function(addr, d)
      if addr == cpu.state["PC"].value and (not bank or mem:read_u8(S.S_BANK) == bank) and n[name] < 40 then
        n[name] = n[name] + 1
        out:write(string.format("%6d %s\n", f, name)); out:flush()
      end
      return d end)
  end
end
emu.register_frame_done(function() f = f + 1 end)
if os.getenv("JUMP") then dofile(os.getenv("PROBES") .. "/p7800-jumpto.lua")
else dofile(os.getenv("PROBES") .. "/playkey.lua") end
