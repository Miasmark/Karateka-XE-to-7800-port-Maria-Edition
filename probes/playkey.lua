-- a scripted player keyed on the game's own progress, for comparing the port
-- with the original: counts calls of $0862 (buffer flip and frame wait in the
-- title and story; on the 7800 at $9862) and of $B60F (the same in play) and, from flip K0 (default 170), holds right for flips
-- 0-12 of every 30 and presses fire at 20-21; dumps both framebuffers at
-- each flip in KEYN to fbk<N>.bin and logs $D0 there to playkey.log; stops
-- after the last, or after END frames (default 6000; the flip count every
-- 100 frames goes to the log). MACHINE=xe for the original.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local xe = os.getenv("MACHINE") == "xe"
local K = 0x0862 + (xe and 0 or 0x9000)
-- gameplay flips at bank 15's $B60F instead; on the 7800 at KEYB (from the
-- build's symbol file, K_B60F)
local KB = xe and 0xB60F or tonumber(os.getenv("KEYB") or "0", 16)
if not xe and KB == 0 then   -- from the build's symbol file
  dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
  KB = SYM_ADDR.K_B60F
end
local K0 = tonumber(os.getenv("K0") or "170")
local A, B = xe and 0x4808 or 0x5808, xe and 0x3010 or 0x4010
local ZD0 = xe and 0xD0 or tonumber(os.getenv("ZD0") or "D0", 16)
local want, last = {}, 0
for n in (os.getenv("KEYN") or "300"):gmatch("%d+") do want[tonumber(n)] = true; last = math.max(last, tonumber(n)) end
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local function press(n, on) if fields[n] then fields[n]:set_value(on and 1 or 0) end end
local n = 0
local log = io.open("playkey.log", "w")
-- ZPLOG: from flip ZPFROM on, the game's zero page (XEGS $00-$FF; on the
-- 7800 through the build's map, ZPMAP) at every flip, to zp.log
local ZMAP = {}
for z = 0, 255 do ZMAP[z] = z end
if not xe and os.getenv("ZPMAP") then
  for line in io.lines(os.getenv("ZPMAP")) do
    local z, t = line:match("^(%x+) (%x+)")
    if z then ZMAP[tonumber(z, 16)] = tonumber(t, 16) end
  end
end
local ZPFROM = tonumber(os.getenv("ZPFROM") or "-1")
-- KEYLOG=1: which address each counted flip was (from ZPFROM), to keys.log
KEYLOG = os.getenv("KEYLOG") and io.open("keys.log", "w") or nil
local zlog = ZPFROM >= 0 and io.open("zp.log", "w") or nil
-- ZW: a game zero-page byte (XEGS address, hex) whose writes are logged
-- with the flip, PC and value from flip ZPFROM on, to zw.log
if os.getenv("ZW") then
  local zw = io.open("zw.log", "w")
  local za = ZMAP[tonumber(os.getenv("ZW"), 16)]
  ZWT = mem:install_write_tap(za, za, "zw", function(a, d)
    if n >= ZPFROM then zw:write(string.format("flip %d PC=%04X <-%02X\n", n, PCs.value, d)); zw:flush() end
    return d end)
end
-- INJECT=1: rather than pressing MAME's inputs (latched at frame boundaries,
-- which fall at different points of the game on the two machines), feed
-- the stick and fire straight into the game's reads: XEGS PORTA ($D300) and
-- TRIG0 ($D010); 7800 SWCHA ($0280) and INPT4 ($0C), with SWCHB's left
-- difficulty bit forced to B (no quick-stick latch)
local INJECT = os.getenv("INJECT") ~= nil
local rightOn, fireOn, leftOn = false, false, false
-- SHORT=1: fire for one flip, not two (the VBI times a press in frames: 20 or
-- more is the other move, and two flips straddle that on the slower machine)
local SHORT = os.getenv("SHORT") ~= nil
local FIREFLAG = os.getenv("FIREFLAG") ~= nil
local QUIET = tonumber(os.getenv("QUIET") or "-1")
local RUN = tonumber(os.getenv("RUN") or "-1")
if INJECT then
  if xe then
    IJ1 = mem:install_read_tap(0xD300, 0xD300, "ijs", function(a, d)
      return (d & 0xF0) | (rightOn and 0x07 or leftOn and 0x0B or 0x0F) end)
    IJ2 = mem:install_read_tap(0xD010, 0xD010, "ijf", function(a, d)
      return fireOn and 0 or 1 end)
  else
    IJ1 = mem:install_read_tap(0x0280, 0x0280, "ijs", function(a, d)
      return (d & 0x0F) | (rightOn and 0x70 or leftOn and 0xB0 or 0xF0) end)
    IJ2 = mem:install_read_tap(0x000C, 0x000C, "ijf", function(a, d)
      return fireOn and (d & 0x7F) or (d | 0x80) end)
    IJ3 = mem:install_read_tap(0x0282, 0x0282, "ijd", function(a, d)
      return d & 0xBF end)
    -- the port reads RIOT once a frame into S_RSWCHA/B and the game's stick
    -- reads use that copy: inject there too, so the game sees the stick as it
    -- is when it reads, as on the XEGS
    dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
    -- (only once the cartridge runs: the BIOS uses that RAM too)
    if SYM_ADDR.S_RSWCHA then
      local cart = false
      IJ6 = mem:install_read_tap(SYM_ADDR.Reset, SYM_ADDR.Reset, "ijon", function(a, d)
        if a == PCs.value then cart = true end
        return d end)
      IJ4 = mem:install_read_tap(SYM_ADDR.S_RSWCHA, SYM_ADDR.S_RSWCHA, "ijsa", function(a, d)
        if not cart then return d end
        return (d & 0x0F) | (rightOn and 0x70 or leftOn and 0xB0 or 0xF0) end)
      IJ5 = mem:install_read_tap(SYM_ADDR.S_RSWCHB, SYM_ADDR.S_RSWCHB, "ijsb", function(a, d)
        if not cart then return d end
        return d & 0xBF end)
    end
  end
end
-- A flip counts when its instruction runs: MAME fetches the opcode, and if
-- an interrupt is taken there, fetches it again after the RTI; so a key
-- fetch only arms the count, and the next fetch confirms it when it is the
-- instruction's successor ($0862 JSR $0878: $0878, +$16; $B60F LDA abs: +3)
-- SCENE: substitute this scene for the game-start write of $D0 = 1 (as the
-- census does), to reach scenes 2, 3, 4 and 6 directly
local SCENE = tonumber(os.getenv("SCENE") or "1")
local subst = false
if SCENE ~= 1 then
  SC = mem:install_write_tap(ZD0, ZD0, "scene", function(a, d)
    if not subst and d == 1 then
      subst = true
      -- HANDOVER=1: also what the previous scene's handover sets (scene 3's
      -- end, for scene 4: $0AFC=$AA, $0AFE=$FF, $B0=8; FINDINGS "The
      -- princess room"); on the 7800 through the carve map
      if os.getenv("HANDOVER") then
        local afc = xe and 0x0AFC or 0x1A86
        mem:write_u8(afc, 0xAA); mem:write_u8(afc + 2, 0xFF); mem:write_u8(ZMAP[0xB0], 8)
      end
      return SCENE
    end
    return d end)
end
local armed = nil
-- (on the 7800, $0862's home $9862 is in the banked window: a fetch there
-- is the game's only with the scene's page in, S_BANK = S_SCENEBANK; bank
-- 5's own code can sit at $9862 too)
local SB, SSB
if not xe then
  dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
  SB, SSB = SYM_ADDR.S_BANK, SYM_ADDR.S_SCENEBANK
end
local function key(a, d)
  if a ~= PCs.value then return d end
  if a == K and SB and mem:read_u8(SB) ~= mem:read_u8(SSB) then return d end
  armed = a
  return d
end
-- SNAPK: flips (comma list) at which to take a screenshot
local SNAPK = {}
for k in (os.getenv("SNAPK") or ""):gmatch("%d+") do SNAPK[tonumber(k)] = true end
-- HOLDS=F: from flip F on, the player's and the foe's health ($B6, $B7) set
-- at every flip to each pair below in turn, 12 flips a pair (the status
-- bar's arrow counts; the low ones last, as they end the fight)
local HOLDS = tonumber(os.getenv("HOLDS") or "-1")
local HPAIRS = {}
for k = 3, 26 do HPAIRS[#HPAIRS + 1] = {k, 28 - k} end
for _, p in ipairs({{4, 4}, {25, 3}, {3, 25}, {2, 26}, {1, 27}, {2, 2}, {1, 1}, {3, 3}, {1, 2}, {2, 1},
                    {27, 1}, {24, 1}, {1, 24}}) do HPAIRS[#HPAIRS + 1] = p end
-- HPAIRS="p:f,p:f,...": those pairs instead
if os.getenv("HPAIRS") then
  HPAIRS = {}
  for p, f in os.getenv("HPAIRS"):gmatch("(%d+):(%d+)") do HPAIRS[#HPAIRS + 1] = {tonumber(p), tonumber(f)} end
end
-- SNAPEND=1: SNAPK's screenshots at the end of the frame instead (a whole
-- frame; at the flip itself the picture can be torn: the frame half drawn)
local SNAPEND = os.getenv("SNAPEND")
-- SNAPDL=1: at the end of the first frame after the flip's display list
-- change (DPPH/DPPL, $2C/$30, written with another list than at the flip:
-- the swap shown): the flip's picture whole, whatever the time the flip
-- took (7800 only)
local SNAPDL = os.getenv("SNAPDL") and not xe
local snapdue, dlwait, dpp, dppat = false, false, {[0x2C] = 0, [0x30] = 0}, nil
if SNAPDL then
  TDL = mem:install_write_tap(0x2C, 0x30, "snapdl", function(a, d)
    if a ~= 0x2C and a ~= 0x30 then return end
    dpp[a] = d
    if dlwait and dpp[0x2C] * 256 + dpp[0x30] ~= dppat then dlwait = false; snapdue = true end
  end)
end
local function counted(a, d)
  n = n + 1
  if SNAPK[n] then
    if SNAPDL then dlwait = true; dppat = dpp[0x2C] * 256 + dpp[0x30] elseif SNAPEND then snapdue = true else M.video:snapshot() end
  end
  PLAYKEY_N = n
  if HOLDS >= 0 and n >= HOLDS then
    local p = HPAIRS[(n - HOLDS) // 12 + 1]
    if p then mem:write_u8(ZMAP[0xB6], p[1]); mem:write_u8(ZMAP[0xB7], p[2]) end
  end
  if KEYLOG and n >= ZPFROM then
    -- with the frame-pacing bytes $0AFC-$0AFE (carved to $1A86 on the 7800)
    -- and the buffer select $07
    local P = xe and 0x0AFC or 0x1A86
    KEYLOG:write(string.format("flip %d at %04X SP=%02X AFC-E=%02X %02X %02X 07=%02X\n", n, a,
      cpu.state["SP"].value & 0xFF, mem:read_u8(P), mem:read_u8(P + 1), mem:read_u8(P + 2), mem:read_u8(ZMAP[7])))
    KEYLOG:flush()
  end
  if n >= K0 then
    local ph = (n - K0) % 30
    rightOn, fireOn = ph <= 12, ph == 20 or (ph == 21 and not SHORT)
    -- QUIET=n: from flip n on, left held and nothing else (the player walks
    -- off the cliff: the game over and "the end" follow)
    if QUIET >= 0 and n >= QUIET then rightOn, fireOn, leftOn = false, false, true; ph = -1 end
    -- RUN=n: from flip n on, right held and nothing else (the player runs on)
    if RUN >= 0 and n >= RUN then rightOn, fireOn, leftOn = true, false, false; ph = -1 end
    if FIREFLAG then
      -- FIREFLAG=1: the press as the game's own short-press flag ($47, which its
      -- VBI sets from the trigger), set as the flip starts on both machines, so
      -- where each machine's VBI falls against the main loop cannot matter; the
      -- trigger itself stays up
      if ph == 20 and mem:read_u8(ZMAP[0x46]) ~= 0xFF then mem:write_u8(ZMAP[0x47], 0xFF) end
      fireOn = false
    end
    if not INJECT then press("P1 Right", rightOn); press("P1 Left", leftOn); press("P1 Button 1", fireOn) end
  end
  if zlog and n >= ZPFROM then
    local t = {}
    for z = 0, 255 do t[#t + 1] = string.format("%02X", mem:read_u8(ZMAP[z])) end
    zlog:write(n .. " " .. table.concat(t, " ") .. "\n"); zlog:flush()
  end
  if want[n] then
    local o = io.open(string.format("fbk%d.bin", n), "wb")
    for bi, base in ipairs({A, B}) do
      local t = {}
      if xe then
        for i = 0, 0x17E7 do t[#t + 1] = string.char(mem:read_u8(base + i)) end
      else
        -- the 7800's rows are one page apart (layout7800 fb_row: pages
        -- FB_PTOP down, six 40-byte rows a page from byte 16; A columns 0-2,
        -- B 3-5, FB_BAND rows a column; a build without them in its symbol
        -- file: $72 and 51): dumped row by row as the XEGS lays them out
        if not SYM_ADDR then dofile(os.getenv("PROBES") .. "/p7800-sym.lua") end
        local BAND, PTOP = SYM_ADDR.FB_BAND or 51, SYM_ADDR.FB_PTOP or 0x72
        local TOP = SYM_ADDR.FB_TOP or 0     -- rows above it: not in the buffers (objects)
        for r = 0, 145 do
          if r < TOP then
            for i = 0, 39 do t[#t + 1] = string.char(0) end
          else
            local rr = r - TOP
            local col = 3 * (bi - 1) + rr // BAND
            local at = (PTOP - rr % BAND) * 256 + 16 + 40 * col
            for i = 0, 39 do t[#t + 1] = string.char(mem:read_u8(at + i)) end
          end
        end
        -- the status rows (146-152) are what MARIA shows there: the
        -- buffer's status list (layout7800 STATUS_DLA/B) drawn on blank,
        -- a 7-row zone whose bottom row is at page hi (a build without the
        -- lists: the rows themselves)
        local px = {}
        for r = 0, 6 do px[r] = {} for x = 0, 159 do px[r][x] = 0 end end
        if not SYM_ADDR then dofile(os.getenv("PROBES") .. "/p7800-sym.lua") end
        local dl = (bi == 1) and SYM_ADDR.STATUS_DLA or SYM_ADDR.STATUS_DLB
        if not dl then
          for r = 146, 152 do
            local at = (PTOP - r % BAND) * 256 + 16 + 40 * (3 * (bi - 1) + r // BAND)
            for i = 0, 39 do
              local v = mem:read_u8(at + i)
              for k = 0, 3 do px[r - 146][4 * i + k] = (v >> (6 - 2 * k)) & 3 end
            end
          end
          dl = 0x10000
        end
        while dl < 0x10000 and mem:read_u8(dl + 1) ~= 0 do
          local lo, pw, hi, hp = mem:read_u8(dl), mem:read_u8(dl + 1), mem:read_u8(dl + 2), mem:read_u8(dl + 3)
          local w = (32 - (pw & 31)) & 31
          for r = 0, 6 do
            local at = (hi + 6 - r) * 256 + lo
            for j = 0, w - 1 do
              local v = mem:read_u8(at + j)
              for k = 0, 3 do
                local p = (v >> (6 - 2 * k)) & 3
                local x = (hp + 4 * j + k) & 0xFF
                if p ~= 0 and x < 160 then px[r][x] = p end
              end
            end
          end
          dl = dl + 4
        end
        for r = 0, 6 do
          for i = 0, 39 do
            local v = 0
            for k = 0, 3 do v = v | (px[r][4 * i + k] << (6 - 2 * k)) end
            t[#t + 1] = string.char(v)
          end
        end
      end
      o:write(table.concat(t))
    end
    o:close()
    if os.getenv("SNAPS") then M.video:snapshot() end   -- SNAPS=1: the screen too
    log:write(string.format("flip %d D0=%02X at f%d\n", n, mem:read_u8(ZD0), PK_FRAME or -1))
    log:flush()
    if n >= last then log:close(); M:exit() end
  end
  return d end
T = mem:install_read_tap(K, K, "key", key)
TB = mem:install_read_tap(KB, KB, "keyb", key)
TN = mem:install_read_tap(0x0000, 0xFFFF, "keynext", function(a, d)
  if armed == nil or a ~= PCs.value or a == armed then return d end
  local k = armed
  armed = nil
  -- (the enhancement fork puts a JSR at $B60F, and one at $0862 in place of
  -- its JSR $0878: their targets confirm too)
  local kbjsr = (mem:read_u8(KB) == 0x20) and (mem:read_u8(KB + 1) + mem:read_u8(KB + 2) * 256) or nil
  local kjsr = (not xe and mem:read_u8(K) == 0x20) and (mem:read_u8(K + 1) + mem:read_u8(K + 2) * 256) or nil
  if (k == K and (a == K + 0x16 or a == kjsr)) or (k == KB and (a == KB + 3 or a == kbjsr)) then return counted(k, d) end
  return d end)
local END = tonumber(os.getenv("END") or "6000")
local SNAPAT = tonumber(os.getenv("SNAPAT") or "-1")   -- a snapshot at this frame
local f = 0
emu.register_frame_done(function()
  if snapdue then snapdue = false; M.video:snapshot() end
  f = f + 1
  PK_FRAME = f                 -- (global: the flip log above reads it)
  if f % 100 == 0 then
    log:write(string.format("f%d flips %d D0=%02X PC=%04X SP=%02X\n", f, n, mem:read_u8(ZD0), PCs.value,
      cpu.state["SP"].value & 0xFF))
    log:flush()
  end
  if SNAPAT and f == SNAPAT then M.video:snapshot() end
  if f >= END then log:close(); M:exit() end
end)
