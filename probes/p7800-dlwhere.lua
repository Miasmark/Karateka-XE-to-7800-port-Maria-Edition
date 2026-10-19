-- Where every scene's display lists are (the user: display lists only in
-- console RAM): at the end of every frame, the shown DLL (DPPH/DPPL as
-- written) walked; each zone's list counted as in console RAM ($0000-$3FFF)
-- or cart RAM ($4000-$7FFF) or ROM, by scene ($D0 through ZPMAP) and by
-- the zone's first line (in groups of 16), with the most bytes a frame's
-- cart-RAM lists took. With playkey.lua (NOPLAYKEY=1: as p7800-stateplay.lua's
-- companion). dlwhere.log when the run stops.
if not os.getenv("NOPLAYKEY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local ZM = {}
for z = 0, 255 do ZM[z] = z end
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZM[tonumber(z, 16)] = tonumber(t, 16) end
end
local dpp = {[0x2C] = 0, [0x30] = 0}
TDW = mem:install_write_tap(0x2C, 0x30, "dwdpp", function(a, d)
  if a == 0x2C or a == 0x30 then dpp[a] = d end
end)
local stat = {}          -- scene -> {frames, cart frames, by line group {console, cart}, most cart bytes, lists}
local function listbytes(p)
  local n = 0
  for k = 1, 40 do
    local c1 = mem:read_u8(p + n + 1)
    if c1 & 0x1F == 0 then
      if c1 == 0 then return n + 2 end
      n = n + 5
    else
      n = n + 4
    end
  end
  return n
end
RU_DW = emu.add_machine_frame_notifier(function()
  local sc = mem:read_u8(ZM[0xD0])
  local st = stat[sc]
  if not st then st = {frames = 0, cartf = 0, groups = {}, most = 0, lists = {}}; stat[sc] = st end
  st.frames = st.frames + 1
  local dll = dpp[0x2C] * 256 + dpp[0x30]
  local line, cart = 0, 0
  for e = 0, 90 do
    local b0, hi, lo = mem:read_u8(dll + 3 * e), mem:read_u8(dll + 3 * e + 1), mem:read_u8(dll + 3 * e + 2)
    local h = (b0 & 15) + 1
    local a = hi * 256 + lo
    local g = line // 16
    local gr = st.groups[g] or {0, 0, 0}
    if a < 0x4000 then gr[1] = gr[1] + 1
    elseif a < 0x8000 then
      gr[2] = gr[2] + 1
      cart = cart + listbytes(a)
      st.lists[string.format("%02X", hi)] = true
    else gr[3] = gr[3] + 1 end
    st.groups[g] = gr
    line = line + h
    if line >= 243 then break end           -- (DLL_LINES: MARIA reads no further)
  end
  if cart > 0 then st.cartf = st.cartf + 1 end
  if cart > st.most then st.most = cart end
end)
RU_DWS = emu.add_machine_stop_notifier(function()
  local o = io.open("dlwhere.log", "w")
  for sc, st in pairs(stat) do
    o:write(string.format("scene %d: frames %d, with lists in cart RAM %d, most cart-RAM list bytes a frame %d; their pages",
      sc, st.frames, st.cartf, st.most))
    local pg = {}
    for k in pairs(st.lists) do pg[#pg + 1] = k end
    table.sort(pg)
    o:write(" " .. table.concat(pg, " ") .. "\n")
    for g = 0, 16 do
      local gr = st.groups[g]
      if gr then o:write(string.format("   lines %3d-%3d: zones console %d cart %d ROM %d\n", 16 * g, 16 * g + 15, gr[1], gr[2], gr[3])) end
    end
  end
  o:close()
end)
