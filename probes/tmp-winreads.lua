-- (debug) playkey.lua, plus: the CPU's data reads of the bank window
-- ($8000-$BFFF) made by code in PC ranges (PCS: "lo-hi,lo-hi" hex; default
-- engine part 2's fixed modules), counted by range and by the reading PC, to
-- winreads.log at END - 5 frames: may that code run from another bank?
dofile(os.getenv("PROBES") .. "/playkey.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local R = {}
for lo, hi in (os.getenv("PCS") or "F600-F7FF,F800-F8FF,F900-FCFF,FD00-FEFF"):gmatch("(%x+)-(%x+)") do
  R[#R + 1] = {tonumber(lo, 16), tonumber(hi, 16)}
end
local function rd(a) return mem:read_u8(a) end
local function ea(pc)
  local op = rd(pc)
  local lo, hi = rd(pc + 1), rd(pc + 2)
  local x, y = cpu.state["X"].value & 0xFF, cpu.state["Y"].value & 0xFF
  local cc, bbb = op & 3, (op >> 2) & 7
  if cc == 1 then
    if bbb == 0 then local p = (lo + x) & 0xFF; return rd(p) + 256 * rd((p + 1) & 0xFF) end
    if bbb == 1 then return lo end
    if bbb == 3 then return lo + 256 * hi end
    if bbb == 4 then return (rd(lo) + 256 * rd((lo + 1) & 0xFF) + y) & 0xFFFF end
    if bbb == 5 then return (lo + x) & 0xFF end
    if bbb == 6 then return (lo + 256 * hi + y) & 0xFFFF end
    if bbb == 7 then return (lo + 256 * hi + x) & 0xFFFF end
  elseif cc == 2 or cc == 0 then
    if bbb == 1 then return lo end
    if bbb == 3 then return lo + 256 * hi end
    if bbb == 5 then return (lo + ((op == 0xB6 or op == 0x96) and y or x)) & 0xFF end
    if bbb == 7 then return (lo + 256 * hi + ((op == 0xBE) and y or x)) & 0xFFFF end
  end
  return nil
end
local END = tonumber(os.getenv("END") or "300")
local f, cnt, busy = 0, {}, false
TWR = mem:install_read_tap(0x8000, 0xBFFF, "winr", function(a, d)
  if busy then return d end
  busy = true
  local pc = cpu.state["PC"].value
  if pc ~= a and ea(pc) == a then      -- (the instruction's own data read, not MARIA's)
    for _, r in ipairs(R) do
      if pc >= r[1] and pc <= r[2] then
        local k = string.format("%04X-%04X pc %04X", r[1], r[2], pc)
        cnt[k] = (cnt[k] or 0) + 1
      end
    end
  end
  busy = false
  return d
end)
RU_WR = emu.add_machine_frame_notifier(function()
  f = f + 1
  if f ~= END - 5 then return end
  local t = {}
  for k, n in pairs(cnt) do t[#t + 1] = {k, n} end
  table.sort(t, function(x, y) return x[1] < y[1] end)
  local o = io.open("winreads.log", "w")
  for _, e in ipairs(t) do o:write(string.format("%s %d\n", e[1], e[2])) end
  o:close()
end)
