"""MARIA's DMA in its own address space, ported by hand into the MAME 0.287
tree (from the private repo's bankset-full.patch, cac5c57, made for MAME
master: its MARIA has a memory view of the BIOS, ours bios_or_cart_r).
Stock MAME has MARIA fetch through the CPU's program space, so a tap or a
watchpoint on it sees MARIA's DMA mixed with the CPU's reads. Now MARIA has
its own space, "dma" (manager.machine.devices[":maria"].spaces["dma"] in
Lua): the CPU's read map, the same RAM (shared), the same cartridge
handlers. A tap on the CPU's space sees only the CPU, one on MARIA's only
MARIA. The rules' handler on $4000-$7FFF stays on the CPU's space; MARIA's
fetches there are its own. Run after mame_bankset.py and mame_bsrules.py.
Usage: python mame_mariaspace.py <mame-src>"""
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
    ('''class atari_maria_device :  public device_t
{''', '''class atari_maria_device :  public device_t, public device_memory_interface
{'''),
    ('''	template <typename T> void set_dmacpu_tag(T &&tag) { m_cpu.set_tag(std::forward<T>(tag)); }
''', '''	template <typename T> void set_dmacpu_tag(T &&tag) { m_cpu.set_tag(std::forward<T>(tag)); }

	// MARIA's own view of the bus, "dma" (address space 0): with a map given it
	// (set_addrmap(AS_DMA, ...)) and set_own_dmaspace(true), MARIA's fetches are its own
	// memory accesses -- a watchpoint or Lua tap on the CPU's space no longer sees them
	static constexpr int AS_DMA = 0;
	void set_own_dmaspace(bool own) { m_own_dmaspace = own; }
'''),
    ('''	virtual void device_start() override ATTR_COLD;
	virtual void device_reset() override ATTR_COLD;
''', '''	virtual void device_start() override ATTR_COLD;
	virtual void device_reset() override ATTR_COLD;
	virtual space_config_vector memory_space_config() const override;
'''),
    ('''	required_device<cpu_device> m_cpu; // CPU whose space(AS_PROGRAM) serves as DMA source''',
     '''	required_device<cpu_device> m_cpu; // CPU whose space(AS_PROGRAM) serves as DMA source (unless its own)
	address_space_config m_dma_config;
	bool m_own_dmaspace = false;
	address_space &dmaspace() { return m_own_dmaspace ? space(AS_DMA) : m_cpu->space(AS_PROGRAM); }'''),
])

patch("src/mame/atari/maria.cpp", [
    ('''	: device_t(mconfig, ATARI_MARIA, tag, owner, clock)
	, m_cpu(*this, finder_base::DUMMY_TAG)''', '''	: device_t(mconfig, ATARI_MARIA, tag, owner, clock)
	, device_memory_interface(mconfig, *this)
	, m_cpu(*this, finder_base::DUMMY_TAG)
	, m_dma_config("dma", ENDIANNESS_LITTLE, 8, 16, 0)'''),
    ('''void atari_maria_device::device_start()
{''', '''device_memory_interface::space_config_vector atari_maria_device::memory_space_config() const
{
	return space_config_vector { std::make_pair(AS_DMA, &m_dma_config) };
}

void atari_maria_device::device_start()
{'''),
    ('''int atari_maria_device::write_line_ram(int addr, uint8_t offset, int pal)
{
	address_space& space = m_cpu->space(AS_PROGRAM);''', '''int atari_maria_device::write_line_ram(int addr, uint8_t offset, int pal)
{
	address_space& space = dmaspace();'''),
    ('''void atari_maria_device::draw_scanline()
{
	address_space& space = m_cpu->space(AS_PROGRAM);''', '''void atari_maria_device::draw_scanline()
{
	address_space& space = dmaspace();'''),
    ('''void atari_maria_device::startdma(int lines)
{
	address_space& space = m_cpu->space(AS_PROGRAM);''', '''void atari_maria_device::startdma(int lines)
{
	address_space& space = dmaspace();'''),
])

H = "read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_%s))"
M = "			m_maria->space(atari_maria_device::AS_DMA).install_read_handler(0x%04x, 0x%04x, " + H + ");\n"
patch("src/mame/atari/a7800.cpp", [
    ('''	void a7800_mem(address_map &map) ATTR_COLD;
''', '''	void a7800_mem(address_map &map) ATTR_COLD;
	void maria_mem(address_map &map) ATTR_COLD;
'''),
    ('''	map(0x0000, 0x01ff).mirror(0x2000).ram(); // 0x40-0xff, 0x140-0x1ff are mirrors of second 6116 chip''',
     '''	map(0x0000, 0x01ff).mirror(0x2000).ram().share("ram_2000"); // 0x40-0xff, 0x140-0x1ff are mirrors of second 6116 chip'''),
    ('''	map(0x1800, 0x1fff).ram();
	map(0x2200, 0x27ff).ram();  // 0x2000-0x21ff, installed in mirror above''',
     '''	map(0x1800, 0x1fff).ram().share("ram_1800");
	map(0x2200, 0x27ff).ram().share("ram_2200");  // 0x2000-0x21ff, installed in mirror above'''),
    ('''	map(0xc000, 0xffff).r(FUNC(a7800_state::bios_or_cart_r));    // here also the BIOS can be accessed
}
''', '''	map(0xc000, 0xffff).r(FUNC(a7800_state::bios_or_cart_r));    // here also the BIOS can be accessed
}

// What MARIA's DMA sees: the CPU's read map, the same RAM (shared), the same cartridge, but its
// own address space, so its fetches are not the CPU's memory accesses -- a watchpoint or a Lua
// tap on the CPU's program space sees only the CPU, one on MARIA's "dma" space only MARIA
void a7800_state::maria_mem(address_map &map)
{
	map(0x0000, 0x01ff).mirror(0x2000).ram().share("ram_2000");
	map(0x0000, 0x001f).mirror(0x300).r(FUNC(a7800_state::tia_r));
	map(0x0020, 0x003f).mirror(0x300).r(m_maria, FUNC(atari_maria_device::read));
	map(0x0280, 0x029f).mirror(0x160).m(m_riot, FUNC(mos6532_device::io_map));
	map(0x0480, 0x04ff).mirror(0x100).m(m_riot, FUNC(mos6532_device::ram_map));
	map(0x1800, 0x1fff).ram().share("ram_1800");
	map(0x2200, 0x27ff).ram().share("ram_2200");
	map(0x4000, 0xbfff).r(m_cart, FUNC(a78_cart_slot_device::read_40xx));
	map(0xc000, 0xffff).r(FUNC(a7800_state::bios_or_cart_r));
}
'''),
    ('''		case A78_HSC:
			// ROM+NVRAM accesses for HiScore
			m_maincpu->space(AS_PROGRAM).install_readwrite_handler(0x1000, 0x17ff, read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_10xx)), write8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::write_10xx)));
			m_maincpu->space(AS_PROGRAM).install_readwrite_handler(0x3000, 0x3fff, read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_30xx)), write8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::write_30xx)));
			break;''', '''		case A78_HSC:
			// ROM+NVRAM accesses for HiScore
			m_maincpu->space(AS_PROGRAM).install_readwrite_handler(0x1000, 0x17ff, read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_10xx)), write8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::write_10xx)));
			m_maincpu->space(AS_PROGRAM).install_readwrite_handler(0x3000, 0x3fff, read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_30xx)), write8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::write_30xx)));
''' + M % (0x1000, 0x17ff, "10xx") + M % (0x3000, 0x3fff, "30xx") + '''			break;'''),
    ('''			// POKEY and RAM regs at 0x400-0x47f
			m_maincpu->space(AS_PROGRAM).install_readwrite_handler(0x0400, 0x047f, read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_04xx)), write8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::write_04xx)));
			break;''', '''			// POKEY and RAM regs at 0x400-0x47f
			m_maincpu->space(AS_PROGRAM).install_readwrite_handler(0x0400, 0x047f, read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_04xx)), write8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::write_04xx)));
''' + M % (0x0400, 0x047f, "04xx") + '''			break;'''),
    ('''			// POKEY and RAM and YM regs at 0x400-0x47f
			m_maincpu->space(AS_PROGRAM).install_readwrite_handler(0x0400, 0x047f, read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_04xx)), write8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::write_04xx)));
			// ROM+NVRAM accesses for HiScore
			m_maincpu->space(AS_PROGRAM).install_readwrite_handler(0x1000, 0x17ff, read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_10xx)), write8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::write_10xx)));
			m_maincpu->space(AS_PROGRAM).install_readwrite_handler(0x3000, 0x3fff, read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_30xx)), write8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::write_30xx)));
			break;''', '''			// POKEY and RAM and YM regs at 0x400-0x47f
			m_maincpu->space(AS_PROGRAM).install_readwrite_handler(0x0400, 0x047f, read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_04xx)), write8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::write_04xx)));
			// ROM+NVRAM accesses for HiScore
			m_maincpu->space(AS_PROGRAM).install_readwrite_handler(0x1000, 0x17ff, read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_10xx)), write8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::write_10xx)));
			m_maincpu->space(AS_PROGRAM).install_readwrite_handler(0x3000, 0x3fff, read8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::read_30xx)), write8sm_delegate(*m_cart, FUNC(a78_cart_slot_device::write_30xx)));
''' + M % (0x0400, 0x047f, "04xx") + M % (0x1000, 0x17ff, "10xx") + M % (0x3000, 0x3fff, "30xx") + '''			break;'''),
    ('''	ATARI_MARIA(config, m_maria, 0);
	m_maria->set_dmacpu_tag(m_maincpu);''', '''	ATARI_MARIA(config, m_maria, 0);
	m_maria->set_dmacpu_tag(m_maincpu);
	m_maria->set_addrmap(atari_maria_device::AS_DMA, &a7800_state::maria_mem);
	m_maria->set_own_dmaspace(true);      // (its DMA its own: mame_mariaspace.py)'''),
])
