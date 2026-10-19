"""The 0.287 tree gets two features of mame-a7800-bankset's bankset-full.patch
(da12f12, made for MAME master): -playback_offset N / -playback_force (the
core's input playback: a recording on a game that starts on another frame)
and -bios skip on a7800 and a7800p (no BIOS: the cartridge starts from its
reset vector as Atari's NTSC BIOS leaves it, at the point in the frame where
7800OpenBIOS hands over). The patch's Activision block order is left out.
After mame_bankset.py, mame_bsrules.py, mame_mariaspace.py:
    python mame_newopts.py C:\\Users\\thuco\\Documents\\mame-src
0.287's a7800 maps the BIOS by INPTCTRL bit 2 (bios_or_cart_r), not by
views as master does, so the skip sets the register instead."""
import os
import sys

TREE = sys.argv[1]


def edit(rel, reps):
    p = os.path.join(TREE, rel)
    a = open(p, encoding="utf-8", newline="").read()
    if "\r\n" in a:                     # (the tree's files keep their own line ends)
        reps = [(o.replace("\n", "\r\n"), n.replace("\n", "\r\n")) for o, n in reps]
    for o, n in reps:
        if n in a:
            continue                    # (already applied)
        if a.count(o) != 1:
            raise SystemExit("%s: anchor not found once: %r" % (rel, o[:60]))
        a = a.replace(o, n)
    open(p, "w", encoding="utf-8", newline="").write(a)
    print("patched", rel)


edit("src/emu/emuopts.h", [
    ('#define OPTION_EXIT_AFTER_PLAYBACK  "exit_after_playback"\n',
     '#define OPTION_EXIT_AFTER_PLAYBACK  "exit_after_playback"\n'
     '#define OPTION_PLAYBACK_OFFSET      "playback_offset"\n'
     '#define OPTION_PLAYBACK_FORCE       "playback_force"\n'),
    ('	bool exit_after_playback() const { return bool_value(OPTION_EXIT_AFTER_PLAYBACK); }\n',
     '	bool exit_after_playback() const { return bool_value(OPTION_EXIT_AFTER_PLAYBACK); }\n'
     '	int playback_offset() const { return int_value(OPTION_PLAYBACK_OFFSET); }\n'
     '	bool playback_force() const { return bool_value(OPTION_PLAYBACK_FORCE); }\n'),
])

edit("src/emu/emuopts.cpp", [
    ('"close the program at the end of playback" },\n',
     '"close the program at the end of playback" },\n'
     '	{ OPTION_PLAYBACK_OFFSET,                            "0",         core_options::option_type::INTEGER,    '
     '"line up a playback with a game that starts on another frame: N > 0 drops the input file\'s first N frames, '
     'N < 0 waits N frames before playing it (implies -playback_force)" },\n'
     '	{ OPTION_PLAYBACK_FORCE,                             "0",         core_options::option_type::BOOLEAN,    '
     '"keep playing back when the input file\'s frame times do not match this run\'s, instead of stopping (\\"Out of sync\\")" },\n'),
])

edit("src/emu/ioport.h", [
    ('	void playback_port(ioport_port &port);\n',
     '	void playback_port(ioport_port &port);\n'
     '	void playback_port_read(ioport_port &port);\n'),
    ('	u32                     m_playback_accumulated_frames; // accumulated frames during playback\n',
     '	u32                     m_playback_accumulated_frames; // accumulated frames during playback\n'
     '	u32                     m_playback_drop = 0;    // input file frames still to drop (-playback_offset > 0)\n'
     '	u32                     m_playback_hold = 0;    // frames still to wait before playing (-playback_offset < 0)\n'
     '	bool                    m_playback_holding = false; // this frame is one of those\n'
     '	bool                    m_playback_force = false;   // keep going when frame times differ\n'
     '	bool                    m_playback_sync_noted = false;\n'),
])

edit("src/emu/ioport.cpp", [
    ('''		osd_printf_info("Input file is for machine '%s', not for current machine '%s'\\n", sysname, machine().system().name);

	// enable compression
''',
     '''		osd_printf_info("Input file is for machine '%s', not for current machine '%s'\\n", sysname, machine().system().name);

	// lining a recording up with a game that starts on another frame (another BIOS, a re-signed
	// or patched build) shifts its frame times, so an offset implies forcing past them
	int const offset = machine().options().playback_offset();
	m_playback_drop = (offset > 0) ? offset : 0;
	m_playback_hold = (offset < 0) ? -offset : 0;
	m_playback_holding = false;
	m_playback_force = machine().options().playback_force() || offset != 0;
	m_playback_sync_noted = false;
	if (offset > 0)
		osd_printf_info("Playback offset: dropping the input file's first %d frames\\n", offset);
	else if (offset < 0)
		osd_printf_info("Playback offset: waiting %d frames before playing the input file\\n", -offset);

	// enable compression
'''),
    ('''	if (m_playback_stream)
	{
		// first the absolute time
		seconds_t seconds_temp;
		attoseconds_t attoseconds_temp;
		playback_read(seconds_temp);
		playback_read(attoseconds_temp);
		attotime readtime(seconds_temp, attoseconds_temp);
		if (readtime != curtime)
			playback_end("Out of sync");
''',
     '''	if (m_playback_stream)
	{
		// -playback_offset < 0: not yet
		m_playback_holding = m_playback_hold != 0;
		if (m_playback_holding)
		{
			m_playback_hold--;
			return;
		}

		// -playback_offset > 0: read past the first frames (each port's values are read
		// into the port and then overwritten by the frame that is played)
		for ( ; m_playback_drop && m_playback_stream; m_playback_drop--)
		{
			seconds_t seconds_skip;
			attoseconds_t attoseconds_skip;
			u32 speed_skip;
			playback_read(seconds_skip);
			playback_read(attoseconds_skip);
			playback_read(speed_skip);
			for (auto &port : m_portlist)
				playback_port_read(*port.second.get());
		}

		// first the absolute time
		seconds_t seconds_temp;
		attoseconds_t attoseconds_temp;
		playback_read(seconds_temp);
		playback_read(attoseconds_temp);
		attotime readtime(seconds_temp, attoseconds_temp);
		if (readtime != curtime && m_playback_stream)
		{
			if (!m_playback_force)
				playback_end("Out of sync");
			else if (!m_playback_sync_noted)
			{
				m_playback_sync_noted = true;
				osd_printf_info("Playback: the input file's frame times differ from this run's; playing on (forced)\\n");
			}
		}
'''),
    ('''void ioport_manager::playback_port(ioport_port &port)
{
	// if playing back, fetch information about this port
	if (m_playback_stream)
''',
     '''void ioport_manager::playback_port(ioport_port &port)
{
	// if playing back, fetch information about this port
	if (!m_playback_holding)
		playback_port_read(port);
}

void ioport_manager::playback_port_read(ioport_port &port)
{
	if (m_playback_stream)
'''),
])

edit("src/mame/atari/a7800.cpp", [
    ('	int m_bios_enabled;\n',
     '	int m_bios_enabled;\n'
     '	uint8_t m_skip_bios = 0;        // the -bios number of "skip" on this machine (mame_newopts.py)\n'),
    ('''void a7800_state::machine_reset()
{
	m_ctrl_lock = 0;
	m_ctrl_reg = 0;
	m_maria_flag = 0;
	m_bios_enabled = 0;
}''',
     '''void a7800_state::machine_reset()
{
	m_ctrl_lock = 0;
	m_ctrl_reg = 0;
	m_maria_flag = 0;
	m_bios_enabled = 0;

	if (system_bios() == m_skip_bios)
	{
		// no BIOS: start where Atari's NTSC BIOS leaves a signed cartridge (docs/bios.md in
		// the a7800 toolkit): INPTCTRL $16 (MARIA on, BIOS off, not locked), X = SP = $16,
		// decimal set, interrupts masked, MARIA's DMA off. The CPU's reset sequence still
		// runs (the cartridge's own reset vector; SP down by 3, I set). Not checked: the
		// signature. RAM is left as MAME has it. (0.287: INPTCTRL bit 2 maps the BIOS out,
		// bios_or_cart_r, where master disables its views)
		m_ctrl_reg = 0x16;
		m_maria_flag = 1;
		m_maincpu->set_state_int(M6502_S, 0x0116 + 3);
		m_maincpu->set_state_int(M6502_X, 0x16);
		m_maincpu->set_state_int(M6502_P, m_maincpu->state_int(M6502_P) | 0x08);

		// at the point in the frame where 7800OpenBIOS hands over (frame 322, in vertical
		// blank), so a recording made under it lines up with -playback_offset 322: PAL 1,653
		// cycles into the frame, NTSC 972 (971.69; MAME's whole-Hz CPU clock). The reset
		// sequence's 7 cycles come out of the wait
		int const handover = m_ispal ? 1653 : 972;
		attotime const frame = (machine().time() == attotime::zero) ? attotime::zero : m_screen->time_until_pos(0, 0);
		m_maincpu->spin_until_time(frame + m_maincpu->cycles_to_attotime(handover - 7));
	}
}'''),
    ('''	ROMX_LOAD("c300558-001a.u7", 0x0000, 0x4000, CRC(a0e10edf) SHA1(14584b1eafe9721804782d4b1ac3a4a7313e455f), ROM_BIOS(1))
ROM_END''',
     '''	ROMX_LOAD("c300558-001a.u7", 0x0000, 0x4000, CRC(a0e10edf) SHA1(14584b1eafe9721804782d4b1ac3a4a7313e455f), ROM_BIOS(1))
	ROM_SYSTEM_BIOS( 2, "skip", "None (boot straight into the cartridge)" )
ROM_END'''),
    ('''	ROM_LOAD("c300558-001b.u7", 0x0000, 0x4000, CRC(d5b61170) SHA1(5a140136a16d1d83e4ff32a19409ca376a8df874))
ROM_END''',
     '''	ROM_SYSTEM_BIOS( 0, "a7800p", "Atari 7800 (PAL)" )
	ROMX_LOAD("c300558-001b.u7", 0x0000, 0x4000, CRC(d5b61170) SHA1(5a140136a16d1d83e4ff32a19409ca376a8df874), ROM_BIOS(0))
	ROM_SYSTEM_BIOS( 1, "skip", "None (boot straight into the cartridge)" )
ROM_END'''),
    ('''	m_ispal = false;
	m_lines = 263;
''',
     '''	m_ispal = false;
	m_lines = 263;
	m_skip_bios = 3;  // system_bios() counts from 1
'''),
    ('''	m_ispal = true;
	m_lines = 313;
''',
     '''	m_ispal = true;
	m_lines = 313;
	m_skip_bios = 2;
'''),
])
print("ok")
