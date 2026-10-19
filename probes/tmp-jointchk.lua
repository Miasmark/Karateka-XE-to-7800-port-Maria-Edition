-- (debug) a companion of p7800-stateplay.lua (SPALSO): level 2's joints
-- (V2, FINDINGS "Level 2's windows: the joints as one entry"). Each L2Joint
-- call (its entry: an opcode fetch, the joint's piece S_TI, its left pixel
-- S_TL, the buffer S_TBUF) is noted; at each flip, a buffer drawn since the
-- last has its joints entry (TOPLI the plain joint's piece) checked against
-- them: the same pixels (TOPLX + 32k for 8k in TOPLK0-TOPLK1), and each
-- drawn mirrored iff from pixel 84 (or off the left plain). To jointchk.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local sym = {}
for l in io.lines(os.getenv("SYM")) do local a, n = l:match("(%x+) (%S+)"); if a then sym[n] = tonumber(a, 16) end end
local AT = sym.L1Joint or sym.L2Joint
local MAX = 28
local log = io.open("jointchk.log", "w")
local seen = {}           -- buffer (0, 1) -> {x = mirrored}
local plainp = {}
local ok, bad, last = 0, 0, -1
local function r(a) return mem:read_u8(a) end
JCK_TAP = mem:install_read_tap(AT, AT, "jchk", function(a, d)
  if cpu.state["PC"].value == AT and r(sym.G_ZD0) == 2 then
    local b = r(sym.S_TBUF) == 0 and 0 or 1
    local p = r(sym.S_TI)
    local mir = (r(sym.TOP_FLAGS + p) & 0x80) ~= 0
    local x = r(sym.S_TL)
    seen[b] = seen[b] or {}
    seen[b][x] = mir
    if not mir then plainp[b] = p else plainp[b] = p - 1 end
  end
  return d
end)
local function check(n, b)
  local s = seen[b]
  local k = r(sym.TOPLN + b)
  local e = nil
  for i = 0, k - 1 do
    if r(sym.TOPLI + b * MAX + i) == plainp[b] then e = b * MAX + i end
  end
  local got = {}
  if e then
    local x0, k0, k1 = r(sym.TOPLX + e), r(sym.TOPLK0 + e), r(sym.TOPLK1 + e)
    local off = 0
    while off < k1 do
      if off >= k0 then got[(x0 + 4 * off) & 0xFF] = true end
      off = off + 8
    end
  end
  local msg = {}
  for x, mir in pairs(s) do
    if not got[x] then msg[#msg + 1] = string.format("drawn %d not in the entry", x) end
    local want = not (x >= 160 or x < 84)
    if mir ~= want then msg[#msg + 1] = string.format("%d drawn %s", x, mir and "mirrored" or "plain") end
  end
  for x in pairs(got) do
    if s[x] == nil then msg[#msg + 1] = string.format("entry's %d not drawn", x) end
  end
  if #msg == 0 then ok = ok + 1 else
    bad = bad + 1
    log:write(string.format("flip %d buffer %d: %s\n", n, b, table.concat(msg, "; ")))
  end
end
emu.register_frame_done(function()
  local n = _G.STATEPLAY_N or -1
  if n ~= last then
    for b = 0, 1 do
      if seen[b] then check(n, b) end
      seen[b] = nil
    end
    last = n
    if n % 50 == 0 then
      local o = io.open("jointchk.sum", "w"); o:write(string.format("flip %d checked %d, bad %d\n", n, ok, bad)); o:close()
      log:flush()
    end
  end
end)
emu.add_machine_stop_notifier(function()
  log:write(string.format("checked %d, bad %d\n", ok, bad)); log:close()
end)
