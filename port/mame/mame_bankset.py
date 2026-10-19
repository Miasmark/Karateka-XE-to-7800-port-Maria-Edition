"""Add BankSet carts to MAME 0.287's 7800 driver.

BankSet (7800.8bitdev.org "Bankset Bankswitching"; a7800's bankset.cpp): the
image is two halves, the CPU's first; while MARIA does its DMA it reads the
second. Here:
  - type $2002 (+$0010): SuperGame halves, the half's second-last bank at
    $4000 (A78_BANKSET_SG, "a78_bs_sg")
  - type $6002: + BankSet RAM: 16K each side at $4000; the CPU writes
    MARIA's through $C000-$FFFF (A78_BANKSET_SG_RAM, "a78_bs_sgr")
  - type $2006: + one RAM at $4000 both sides read (A78_BANKSET_SG_SRAM,
    "a78_bs_sgs"; not in the spec, as the openFPGA-7800 core maps it)
The driver tells the cart when MARIA reads (set_maria_dma around startdma).
"""
import sys

ROOT = sys.argv[1]


def edit(path, pairs):
    p = ROOT + "/" + path
    s = open(p, encoding="utf-8").read()
    for old, new in pairs:
        if s.count(old) != 1:
            raise SystemExit("%s: %r found %d times" % (path, old[:60], s.count(old)))
        s = s.replace(old, new)
    open(p, "w", encoding="utf-8", newline="").write(s)
    print("patched", path)


edit("src/devices/bus/a7800/a78_slot.h", [
    ("""	A78_VERSA_POK450 = 0x30
""", """	A78_VERSA_POK450 = 0x30,
	// Bankset (Fred Quimby): two SuperGame halves, the CPU's and MARIA's (outside the ranges above:
	// the VersaBoard's RAM is allocated for types A78_VERSABOARD to A78_VERSA_POK450)
	A78_BANKSET_SG = 0x40,
	A78_BANKSET_SG_RAM = 0x41,  // + 16K RAM each side at $4000 (MARIA's written through $C000-$FFFF)
	A78_BANKSET_SG_SRAM = 0x42  // + one 16K RAM at $4000 both sides read (not in the spec)
"""),
    ("""	uint32_t get_nvram_size() { return m_nvram.size(); }

protected:
	device_a78_cart_interface(const machine_config &mconfig, device_t &device);
""", """	uint32_t get_nvram_size() { return m_nvram.size(); }

	// MARIA's DMA under way (its reads are MARIA's: Bankset carts answer them from their second half)
	void set_maria_dma(bool on) { m_maria_dma = on; }

protected:
	device_a78_cart_interface(const machine_config &mconfig, device_t &device);

	bool m_maria_dma = false;
"""),
    ("""	bool has_cart() { return m_cart != nullptr; }
""", """	bool has_cart() { return m_cart != nullptr; }
	void set_maria_dma(bool on) { if (m_cart) m_cart->set_maria_dma(on); }
"""),
])

TYPES = """
		// Bankset (bit 13): two SuperGame halves; bit 14 Bankset RAM, else bit 2 one shared RAM
		if ((mapper & 0x2002) == 0x2002)
		{
			if (mapper & 0x4000)
				TYPEVAR = A78_BANKSET_SG_RAM;
			else if (mapper & 0x0004)
				TYPEVAR = A78_BANKSET_SG_SRAM;
			else
				TYPEVAR = A78_BANKSET_SG;
		}
"""
edit("src/devices/bus/a7800/a78_slot.cpp", [
    ("""	if ((head & 0xff00) > 0x300)
	{""", """	// Bankset (bit 13; bit 14 its RAM): kept for the type detection
	if ((head & 0x2000) && !(head & 0xff00 & ~0x6000))
		return head;

	if ((head & 0xff00) > 0x300)
	{"""),
    ("""	{ A78_VERSABOARD, "a78_versa" },
""", """	{ A78_VERSABOARD, "a78_versa" },
	{ A78_BANKSET_SG, "a78_bs_sg" },
	{ A78_BANKSET_SG_RAM, "a78_bs_sgr" },
	{ A78_BANKSET_SG_SRAM, "a78_bs_sgs" },
"""),
    ("""			else if ((mapper & 0x0080) == 0x0080)
				m_type = A78_TYPE8;

""", """			else if ((mapper & 0x0080) == 0x0080)
				m_type = A78_TYPE8;
""" + TYPES.replace("TYPEVAR", "m_type").replace("\n\t\t", "\n\t\t\t") + """
"""),
    ("""			if (m_type == A78_TYPE6 || m_type == A78_TYPE8)
				m_cart->ram_alloc(0x4000);
""", """			if (m_type == A78_TYPE6 || m_type == A78_TYPE8 || m_type == A78_BANKSET_SG_SRAM)
				m_cart->ram_alloc(0x4000);
			if (m_type == A78_BANKSET_SG_RAM)
				m_cart->ram_alloc(0x8000);
"""),
    ("""		else if ((mapper & 0x0080) == 0x0080)
			type = A78_TYPE8;
""", """		else if ((mapper & 0x0080) == 0x0080)
			type = A78_TYPE8;
""" + TYPES.replace("TYPEVAR", "type")),
])

edit("src/devices/bus/a7800/a78_carts.h", [
    ("""	device.option_add_internal("a78_versa",    A78_ROM_VERSABOARD);
""", """	device.option_add_internal("a78_versa",    A78_ROM_VERSABOARD);
	device.option_add_internal("a78_bs_sg",    A78_ROM_BANKSET_SG);
	device.option_add_internal("a78_bs_sgr",   A78_ROM_BANKSET_SG_RAM);
	device.option_add_internal("a78_bs_sgs",   A78_ROM_BANKSET_SG_SRAM);
"""),
])

edit("src/devices/bus/a7800/rom.h", [
    ("""// ======================> a78_rom_sg_pokey_device
""", """// ======================> a78_rom_bankset_sg_device (Bankset: two SuperGame halves, MARIA reads the second)

class a78_rom_bankset_sg_device : public a78_rom_sg_device
{
public:
	a78_rom_bankset_sg_device(const machine_config &mconfig, const char *tag, device_t *owner, uint32_t clock);

	virtual uint8_t read_40xx(offs_t offset) override;
	virtual void write_40xx(offs_t offset, uint8_t data) override;

protected:
	a78_rom_bankset_sg_device(const machine_config &mconfig, device_type type, const char *tag, device_t *owner, uint32_t clock);

	uint32_t half() const { return m_rom_size / 2; }
	uint32_t side() const { return m_maria_dma ? half() : 0; }
	int banks() const { return half() / 0x4000; }
	uint8_t rom_40xx(offs_t offset);
};


// ======================> a78_rom_bankset_sg_ram_device (+ 16K RAM each side; MARIA's written at $C000-$FFFF)

class a78_rom_bankset_sg_ram_device : public a78_rom_bankset_sg_device
{
public:
	a78_rom_bankset_sg_ram_device(const machine_config &mconfig, const char *tag, device_t *owner, uint32_t clock);

	virtual uint8_t read_40xx(offs_t offset) override;
	virtual void write_40xx(offs_t offset, uint8_t data) override;
};


// ======================> a78_rom_bankset_sg_sram_device (+ one 16K RAM both sides read)

class a78_rom_bankset_sg_sram_device : public a78_rom_bankset_sg_device
{
public:
	a78_rom_bankset_sg_sram_device(const machine_config &mconfig, const char *tag, device_t *owner, uint32_t clock);

	virtual uint8_t read_40xx(offs_t offset) override;
	virtual void write_40xx(offs_t offset, uint8_t data) override;
};


// ======================> a78_rom_sg_pokey_device
"""),
])
# the device types: declared beside the others in rom.h
s = open(ROOT + "/src/devices/bus/a7800/rom.h", encoding="utf-8").read()
anchor = "DECLARE_DEVICE_TYPE(A78_ROM_SG_RAM,"
if anchor not in s:
    raise SystemExit("rom.h: no DECLARE_DEVICE_TYPE(A78_ROM_SG_RAM")
i = s.index(anchor)
j = s.index("\n", i) + 1
s = s[:j] + """DECLARE_DEVICE_TYPE(A78_ROM_BANKSET_SG,      a78_rom_bankset_sg_device)
DECLARE_DEVICE_TYPE(A78_ROM_BANKSET_SG_RAM,  a78_rom_bankset_sg_ram_device)
DECLARE_DEVICE_TYPE(A78_ROM_BANKSET_SG_SRAM, a78_rom_bankset_sg_sram_device)
""" + s[j:]
open(ROOT + "/src/devices/bus/a7800/rom.h", "w", encoding="utf-8", newline="").write(s)
print("patched rom.h (declarations)")

edit("src/devices/bus/a7800/rom.cpp", [
    ("""DEFINE_DEVICE_TYPE(A78_ROM_SG9,""", """DEFINE_DEVICE_TYPE(A78_ROM_BANKSET_SG,      a78_rom_bankset_sg_device,      "a78_rom_bs_sg",  "Atari 7800 ROM Carts w/Bankset SuperGame")
DEFINE_DEVICE_TYPE(A78_ROM_BANKSET_SG_RAM,  a78_rom_bankset_sg_ram_device,  "a78_rom_bs_sgr", "Atari 7800 ROM Carts w/Bankset SuperGame + RAM")
DEFINE_DEVICE_TYPE(A78_ROM_BANKSET_SG_SRAM, a78_rom_bankset_sg_sram_device, "a78_rom_bs_sgs", "Atari 7800 ROM Carts w/Bankset SuperGame + shared RAM")
DEFINE_DEVICE_TYPE(A78_ROM_SG9,"""),
])
s = open(ROOT + "/src/devices/bus/a7800/rom.cpp", encoding="utf-8").read()
s += '''

/*-------------------------------------------------

 Bankset carts (Fred Quimby; 7800.8bitdev.org "Bankset Bankswitching";
 after a7800's bankset.cpp): the image is two SuperGame halves, the CPU's
 first, MARIA's second (while it does its DMA: set_maria_dma). Each half:
 its second-last bank at $4000 (without RAM), the selected bank at $8000,
 its last at $C000.
 RAM: Bankset RAM gives each side 16K at $4000, the CPU writing MARIA's
 through $C000-$FFFF (it can't read it); the shared variant (header bit 2,
 not in the spec) has one 16K both read.

 -------------------------------------------------*/

a78_rom_bankset_sg_device::a78_rom_bankset_sg_device(const machine_config &mconfig, device_type type, const char *tag, device_t *owner, uint32_t clock)
	: a78_rom_sg_device(mconfig, type, tag, owner, clock)
{
}

a78_rom_bankset_sg_device::a78_rom_bankset_sg_device(const machine_config &mconfig, const char *tag, device_t *owner, uint32_t clock)
	: a78_rom_bankset_sg_device(mconfig, A78_ROM_BANKSET_SG, tag, owner, clock)
{
}

a78_rom_bankset_sg_ram_device::a78_rom_bankset_sg_ram_device(const machine_config &mconfig, const char *tag, device_t *owner, uint32_t clock)
	: a78_rom_bankset_sg_device(mconfig, A78_ROM_BANKSET_SG_RAM, tag, owner, clock)
{
}

a78_rom_bankset_sg_sram_device::a78_rom_bankset_sg_sram_device(const machine_config &mconfig, const char *tag, device_t *owner, uint32_t clock)
	: a78_rom_bankset_sg_device(mconfig, A78_ROM_BANKSET_SG_SRAM, tag, owner, clock)
{
}

uint8_t a78_rom_bankset_sg_device::rom_40xx(offs_t offset)
{
	if (offset < 0x4000)
		return m_rom[side() + (banks() - 2) * 0x4000 + offset];
	else if (offset < 0x8000)
		return m_rom[side() + (m_bank % banks()) * 0x4000 + (offset & 0x3fff)];
	else
		return m_rom[side() + (banks() - 1) * 0x4000 + (offset & 0x3fff)];
}

uint8_t a78_rom_bankset_sg_device::read_40xx(offs_t offset)
{
	return rom_40xx(offset);
}

void a78_rom_bankset_sg_device::write_40xx(offs_t offset, uint8_t data)
{
	if (offset >= 0x4000 && offset < 0x8000)
		m_bank = data & (banks() - 1);
}

uint8_t a78_rom_bankset_sg_ram_device::read_40xx(offs_t offset)
{
	if (offset < 0x4000)
		return m_ram[(m_maria_dma ? 0x4000 : 0) + offset];
	return rom_40xx(offset);
}

void a78_rom_bankset_sg_ram_device::write_40xx(offs_t offset, uint8_t data)
{
	if (offset < 0x4000)
		m_ram[offset] = data;
	else if (offset < 0x8000)
		m_bank = data & (banks() - 1);
	else
		m_ram[0x4000 + (offset & 0x3fff)] = data;
}

uint8_t a78_rom_bankset_sg_sram_device::read_40xx(offs_t offset)
{
	if (offset < 0x4000)
		return m_ram[offset];
	return rom_40xx(offset);
}

void a78_rom_bankset_sg_sram_device::write_40xx(offs_t offset, uint8_t data)
{
	if (offset < 0x4000)
		m_ram[offset] = data;
	else if (offset < 0x8000)
		m_bank = data & (banks() - 1);
}
'''
open(ROOT + "/src/devices/bus/a7800/rom.cpp", "w", encoding="utf-8", newline="").write(s)
print("patched rom.cpp (the carts)")

edit("src/mame/atari/a7800.cpp", [
    ("""TIMER_CALLBACK_MEMBER(a7800_state::maria_startdma)
{
	m_maria->startdma(m_lines);
}""", """TIMER_CALLBACK_MEMBER(a7800_state::maria_startdma)
{
	// MARIA's reads are its DMA's: Bankset carts answer them from their second half
	m_cart->set_maria_dma(true);
	m_maria->startdma(m_lines);
	m_cart->set_maria_dma(false);
}"""),
])
print("done")
