-- (debug) the original's fighter draws (bank 15's $A815) from frame FROM to
-- END: the buffer ($07), $2C (negative the enemy), poses $20/$21/$22, $50,
-- $36, $4D, the stack's first three return addresses, and the box erases
-- ($A780 the enemy's, $A78C the player's), to fighterdraw.log; CHEAT: the
-- script the recording was made with (the ghost player in the embrace: the
-- port's against the original's). WATCH: more addresses (hex, comma list)
-- shown at each
local M = manager.machine
if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "31000")
local watch = {}
for t in (os.getenv("WATCH") or ""):gmatch("%x+") do watch[#watch + 1] = tonumber(t, 16) end
local log = io.open("fighterdraw.log", "w")
local f = 0
local function z(a) return mem:read_u8(a) end
local taps = {}
for _, e in ipairs({{0xA815, "draw"}, {0xA780, "erE"}, {0xA78C, "erP"}}) do
  taps[#taps + 1] = mem:install_read_tap(e[1], e[1], "fd" .. e[2], function(ad, d)
    if f >= FROM and ad == cpu.state["PC"].value then
      local sp = cpu.state["SP"].value
      local function ret(k) return z(0x100 + ((sp + 2 * k - 1) & 0xFF)) + 256 * z(0x100 + ((sp + 2 * k) & 0xFF)) + 1 end
      local w = ""
      for _, a in ipairs(watch) do w = w .. string.format(" %04X=%02X", a, z(a)) end
      log:write(string.format("f%d %s $07=%02X $2C=%02X $20=%02X $21=%02X $22=%02X $50=%02X $36=%02X $4D=%02X ret %04X %04X %04X%s\n",
        f, e[2], z(0x07), z(0x2C), z(0x20), z(0x21), z(0x22), z(0x50), z(0x36), z(0x4D), ret(1), ret(2), ret(3), w))
    end
    return d
  end)
end
FD_TAPS = taps
emu.register_frame_done(function()
  f = f + 1
  if f >= END then log:close(); M:exit() end
end)
