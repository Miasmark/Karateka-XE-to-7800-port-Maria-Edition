-- (debug) the two buttons: presses PRESSES ("1:frame:len,2:frame:len,...":
-- button, first frame, frames held; button 1 or 2, or 0 for both), and logs
-- each frame where the game's $DC (button state) changes and every write of
-- $FF to $46 (kick) or $47 (punch) with its PC, to buttons.log; MAME exits at
-- END; snapshots at FRAMES. (Game zero page: ZDC/Z46/Z47 hex, default the 7800 addresses)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local END = tonumber(os.getenv("END") or "3000")
local DC = tonumber(os.getenv("ZDC") or "DC", 16)
local K = tonumber(os.getenv("Z46") or "46", 16)
local P = tonumber(os.getenv("Z47") or "47", 16)
local snaps = {}
for t in (os.getenv("FRAMES") or ""):gmatch("%d+") do snaps[tonumber(t)] = true end
local presses = {}
for b, a, n in (os.getenv("PRESSES") or ""):gmatch("(%d+):(%d+):(%d+)") do
  presses[#presses + 1] = {tonumber(b), tonumber(a), tonumber(n)}
end
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local o = io.open("buttons.log", "w")
local f, last = 0, -1
BT_TAP = mem:install_write_tap(math.min(K, P), math.max(K, P), "btn", function(a, d)
  if d == 0xFF and (a == K or a == P) then
    o:write(string.format("f%d %s pc $%04X\n", f, a == K and "KICK" or "PUNCH", cpu.state["PC"].value))
  end
  return d
end)
emu.register_frame_done(function()
  f = f + 1
  local b1, b2 = 0, 0
  for _, p in ipairs(presses) do
    if f >= p[2] and f < p[2] + p[3] then
      if p[1] == 1 or p[1] == 0 then b1 = 1 end
      if p[1] == 2 or p[1] == 0 then b2 = 1 end
    end
  end
  if fields["P1 Button 1"] then fields["P1 Button 1"]:set_value(b1) end
  if fields["P1 Button 2"] then fields["P1 Button 2"]:set_value(b2) end
  local v = mem:read_u8(DC)
  if v ~= last then o:write(string.format("f%d $DC %02X (b1 %d b2 %d)\n", f, v, b1, b2)); last = v end
  if snaps[f] then M.video:snapshot() end
  if f >= END then o:close(); M:exit() end
end)
