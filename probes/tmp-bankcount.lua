dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local S = SYM_ADDR
local cnt, l1cnt, f = {}, {}, 0
TBC = mem:install_write_tap(0x8000, 0x8000, "bankc", function(a, d)
  cnt[d] = (cnt[d] or 0) + 1
  if mem:read_u8(S.S_L1) == 1 then l1cnt[d] = (l1cnt[d] or 0) + 1 end
end)
emu.register_frame_done(function()
  f = f + 1
  if f == tonumber(os.getenv("END")) - 5 then
    local o = io.open("bankcount.log", "w")
    for k, v in pairs(cnt) do o:write(string.format("bank %d all %d level1 %d\n", k, v, l1cnt[k] or 0)) end
    o:close()
  end
end)
