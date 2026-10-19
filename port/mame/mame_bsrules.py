"""The BankSet spec's two rules for cartridge RAM, ported by hand into the
MAME 0.287 tree (from the private repo's bankset-full.patch, 8afcd93, made
for MAME master): on a BankSet cartridge with RAM (our a78_bs_sgr $6002 and
a78_bs_sgs $2006 forms)
  - MARIA's display lists and display list list fetched from $4000-$7FFF
    read 0 (the list ends), with one warning: "Your DL must be stored in
    console ram, rather than bankset cart ram";
  - an opcode the CPU fetches from $4000-$7FFF reads $FF, with one warning:
    "execution from Sally's cart-ram isn't supported".
MARIA's graphics reads and the CPU's data reads are untouched.
Usage: python mame_bsrules.py <mame-src>"""
import sys

T = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\thuco\Documents\mame-src"


def patch(rel, pairs):
    p = T + "/" + rel
    s = open(p, encoding="utf-8").read()
    for pr in pairs:
        o, n = pr[0], pr[1]
        mark = pr[2] if len(pr) > 2 else n       # (applied already: its marker is there)
        if mark in s:
            continue
        if s.count(o) != 1:
            raise SystemExit("%s: %d matches for %r" % (rel, s.count(o), o[:60]))
        s = s.replace(o, n)
    open(p, "w", encoding="utf-8", newline="").write(s)
    print("patched", rel)


patch("src/mame/atari/maria.h", [
    ("""	void draw_scanline();
	int is_holey(unsigned int addr);""",
     """	void draw_scanline();
	int is_holey(unsigned int addr);
	uint8_t read_dma(address_space &space, offs_t addr) { m_in_dma_read = true; const uint8_t d = space.read_byte(addr); m_in_dma_read = false; return d; }
	uint8_t read_dl(address_space &space, offs_t addr);
	bool m_in_dma_read = false;
	offs_t m_cart_ram_lo = 1, m_cart_ram_hi = 0;   // (an empty window until the driver sets one)
	bool m_dl_warned = false;"""),
    ("""	uint8_t read(offs_t offset);""",
     """	uint8_t read(offs_t offset);
	// BankSet cartridge RAM's CPU range: display lists fetched from it read as empty (read_dl)
	void set_cart_ram_window(offs_t lo, offs_t hi) { m_cart_ram_lo = lo; m_cart_ram_hi = hi; m_dl_warned = false; }
	// true while MARIA, not the CPU, reads (its DMA goes through the CPU's space)
	bool in_dma_read() const { return m_in_dma_read; }"""),
])

mc = open(T + "/src/mame/atari/maria.cpp", encoding="utf-8").read()
if "READ_DL(" not in mc:
    lines = mc.split("\n")
    out = []
    in_hdr = False
    for i, l in enumerate(lines):
        if l.startswith("#define READ_MEM(x)"):
            out.append("#define READ_MEM(x) read_dma(space, x)")
            out.append("#define READ_DL(x) read_dl(space, x)")
            continue
        # the headers' and the DLL's reads (not the graphics': write_line_ram's
        # and the indirect map's, READ_MEM(graph_adr + x))
        if "READ_MEM(" in l and ("dl" in l.replace("READ_MEM", "")) and "graph_adr + x" not in l:
            l = l.replace("READ_MEM(", "READ_DL(")
        out.append(l)
    mc = "\n".join(out)
    mc += """

// A display list and the display list list are read through here. On a BankSet cartridge with RAM
// they must live in console RAM, not in the cartridge's RAM ("Your DL must be stored in console ram,
// rather than bankset cart ram", 7800.8bitdev.org, Bankset Bankswitching): such a fetch reads 0,
// which ends the list, and says so once.
uint8_t atari_maria_device::read_dl(address_space &space, offs_t addr)
{
	if (addr >= m_cart_ram_lo && addr <= m_cart_ram_hi)
	{
		if (!m_dl_warned)
		{
			osd_printf_warning("MARIA fetched a display list from bankset cartridge space ($%04X): unsupported, "
					"display lists must be in console RAM\\n", addr);
			m_dl_warned = true;
		}
		return 0;
	}
	return read_dma(space, addr);
}
"""
    open(T + "/src/mame/atari/maria.cpp", "w", encoding="utf-8", newline="").write(mc)
    print("patched src/mame/atari/maria.cpp")

patch("src/mame/atari/a7800.cpp", [
    ("""	required_device<cpu_device> m_maincpu;""",
     """	required_device<m6502_device> m_maincpu;
	bool m_cart_ram_exec_warned = false;
	uint8_t bankram_window_r(offs_t offset);"""),
    ("""uint8_t a7800_state::tia_r(offs_t offset)""",
     """// BankSet cartridges with RAM: "execution from Sally's cart-ram isn't supported" (7800.8bitdev.org,
// Bankset Bankswitching). An opcode fetch (the CPU's SYNC) from $4000-$7FFF reads $FF and says so
// once; MARIA's DMA reads come through here too, with the CPU halted, and are told apart by its flag.
uint8_t a7800_state::bankram_window_r(offs_t offset)
{
	if (!machine().side_effects_disabled() && m_maincpu->get_sync() && !m_maria->in_dma_read())
	{
		if (!m_cart_ram_exec_warned)
		{
			osd_printf_warning("the CPU fetched an instruction from bankset cart RAM ($%04X): unsupported on hardware\\n", 0x4000 + offset);
			m_cart_ram_exec_warned = true;
		}
		return 0xff;
	}
	return m_cart->read_40xx(offset);
}

uint8_t a7800_state::tia_r(offs_t offset)"""),
    ("""			m_maincpu->space(AS_PROGRAM).install_readwrite_handler(0x3000, 0x3fff, read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_30xx)), write8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::write_30xx)));
			break;
		}
	}""",
     """			m_maincpu->space(AS_PROGRAM).install_readwrite_handler(0x3000, 0x3fff, read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_30xx)), write8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::write_30xx)));
			break;
		case A78_BANKSET_SG_RAM:
		case A78_BANKSET_SG_SRAM:
			// cartridge RAM: MARIA cannot take its display lists from it, the CPU cannot run code in it
			m_maria->set_cart_ram_window(0x4000, 0x7fff);
			m_maincpu->space(AS_PROGRAM).install_read_handler(0x4000, 0x7fff, read8sm_delegate(*this, FUNC(a7800_state::bankram_window_r)));
			break;
		}
	}""", "a7800_state::bankram_window_r)));\n\t\t\tbreak;"),   # (marker: the window's later form too)
])

# (2026-10-10, the private repo's 1a7dc35 and 6daa5d9) display lists may not
# come from a BankSet cartridge's ROM either: the window is the cartridge's
# whole space, $4000-$FFFF, for every BankSet form; and the -debugger script
# module (a debugger with no window whose stops hold for Lua: breakpoints,
# watchpoints, stepping, traces from autoboot scripts; the toolkit's MCP
# server runs MAME with -debug -debugger script)
import os
import shutil
patch("src/mame/atari/a7800.cpp", [
    ("""		case A78_BANKSET_SG_RAM:
		case A78_BANKSET_SG_SRAM:
			// cartridge RAM: MARIA cannot take its display lists from it, the CPU cannot run code in it
			m_maria->set_cart_ram_window(0x4000, 0x7fff);""",
     """		case A78_BANKSET_SG:
			// a BankSet cartridge: display lists belong in console RAM, not in its ROM or RAM
			m_maria->set_cart_ram_window(0x4000, 0xffff);
			break;
		case A78_BANKSET_SG_RAM:
		case A78_BANKSET_SG_SRAM:
			// cartridge RAM: MARIA cannot take its display lists from it (nor from the ROM), the
			// CPU cannot run code in it
			m_maria->set_cart_ram_window(0x4000, 0xffff);"""),
])
here = os.path.dirname(os.path.abspath(__file__))
dst = T + "/src/osd/modules/debugger/script.cpp"
if not os.path.exists(dst):
    shutil.copy(os.path.join(here, "script.cpp"), dst)
    print("added src/osd/modules/debugger/script.cpp")
patch("scripts/src/osd/modules.lua", [
    ('''		MAME_DIR .. "src/osd/modules/debugger/none.cpp",''',
     '''		MAME_DIR .. "src/osd/modules/debugger/none.cpp",
		MAME_DIR .. "src/osd/modules/debugger/script.cpp",'''),
])
patch("src/osd/modules/lib/osdobj_common.cpp", [
    ("""	REGISTER_MODULE(m_mod_man, DEBUG_NONE);""",
     """	REGISTER_MODULE(m_mod_man, DEBUG_NONE);
	REGISTER_MODULE(m_mod_man, DEBUG_SCRIPT);"""),
])

# 0.287's Lua bpset/wpset build their condition and action strings from a
# missing argument as a null pointer (strlen crashes): give them "1" and ""
# as MAME master does (the toolkit's mcp-server.lua calls bpset(addr))
patch("src/frontend/mame/luaengine_debug.cpp", [
    ("""				int result(dev.breakpoint_set(address, cond, act));""",
     """				int result(dev.breakpoint_set(address, cond ? cond : "1", act ? act : ""));"""),
    ("""				int result(dev.watchpoint_set(sp.space, wptype, addr, len, cond, act));""",
     """				int result(dev.watchpoint_set(sp.space, wptype, addr, len, cond ? cond : "1", act ? act : ""));"""),
])
