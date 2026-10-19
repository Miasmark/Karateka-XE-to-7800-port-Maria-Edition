-- (debug) the original: fire pressed at FIRE1 (8 frames), START held at
-- STARTF (8 frames) if given, left held from LEFT on; snapshots at SNAPS;
-- exits at END
local M = manager.machine
local F1 = tonumber(os.getenv("FIRE1") or "400")
local ST = tonumber(os.getenv("STARTF") or "-1")
local LEFT = tonumber(os.getenv("LEFT") or "900")
local END = tonumber(os.getenv("END") or "2000")
local snaps = {}
for t in (os.getenv("SNAPS") or ""):gmatch("%d+") do snaps[tonumber(t)] = true end
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local names = {}
for n in pairs(fields) do names[#names + 1] = n end
table.sort(names)
local o = io.open("fields.txt", "w"); o:write(table.concat(names, "\n")); o:close()
local f = 0
emu.register_frame_done(function()
  f = f + 1
  local fire = f >= F1 and f < F1 + 8
  if fields["P1 Button 1"] then fields["P1 Button 1"]:set_value(fire and 1 or 0) end
  if fields["Start"] and ST >= 0 then fields["Start"]:set_value((f >= ST and f < ST + 8) and 1 or 0) end
  if fields["P1 Left"] then fields["P1 Left"]:set_value(f >= LEFT and 1 or 0) end
  if snaps[f] then M.video:snapshot() end
  if f >= END then M:exit() end
end)
