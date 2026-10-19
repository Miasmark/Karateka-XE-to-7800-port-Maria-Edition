-- (debug) each frame PFROM-PTO, the bytes of the symbols in MEMSYMS (comma
-- list; name or name+n) at the frame's end, to memlog.log; MAME exits after
-- PTO. SYM: the build's symbol file.
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FR = tonumber(os.getenv("PFROM") or "0")
local TO = tonumber(os.getenv("PTO") or "100")
local names = {}
for t in (os.getenv("MEMSYMS") or ""):gmatch("[^,]+") do names[#names + 1] = t end
local o = io.open("memlog.log", "w")
o:write("frame " .. table.concat(names, " ") .. "\n")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f >= FR and f <= TO then
    local v = {}
    for _, n in ipairs(names) do
      local base, off = n:match("^([%w_]+)%+?(%d*)$")
      local a = S[base]
      v[#v + 1] = a and string.format("%02X", mem:read_u8(a + (tonumber(off) or 0))) or "--"
    end
    o:write(string.format("f%d %s\n", f, table.concat(v, " ")))
  end
  if f > TO then o:close(); M:exit() end
end)
