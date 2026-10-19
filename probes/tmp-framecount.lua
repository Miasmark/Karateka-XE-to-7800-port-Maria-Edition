-- (debug) a frame counter on stdout (with MAME's own warnings in run.out): the first N frames
local f, N = 0, tonumber(os.getenv("N") or "40")
RU_FC = emu.add_machine_frame_notifier(function() f = f + 1; if f <= N then print("-- frame " .. f) end end)
