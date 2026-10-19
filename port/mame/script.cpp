// license:BSD-3-Clause
// copyright-holders:a7800 toolkit contributors
/*******************************************************************************

    script.cpp - a debugger with no window, driven by Lua

    -debugger none resumes the machine the moment it stops, so a script cannot
    use breakpoints, watchpoints or stepping: the stop is over before it can look.
    This one holds the stop and keeps Lua's periodic callbacks running while it
    does, so an autoboot script or plugin can read the stopped machine and decide
    when to go on (manager.machine.debugger.execution_state = "run").

    Used by the a7800 toolkit's MCP server (probes/mcp-server.lua):

        mame a7800 -debug -debugger script -autoboot_script mcp-server.lua ...

*******************************************************************************/

#include "emu.h"
#include "debug_module.h"

#include "modules/osdmodule.h"

#include "emuopts.h"
#include "main.h"

#include "osdcore.h"


namespace osd {

namespace {

class debug_script : public osd_module, public debug_module
{
public:
	debug_script() : osd_module(OSD_DEBUG_PROVIDER, "script"), debug_module(), m_machine(nullptr) { }
	virtual ~debug_script() { }

	virtual int init(osd_interface &osd, const osd_options &options) override { return 0; }
	virtual void exit() override { }

	virtual void init_debugger(running_machine &machine) override { m_machine = &machine; }
	virtual void wait_for_debugger(device_t &device, bool firststop) override;
	virtual void debugger_update() override { }

private:
	running_machine *m_machine;
};

void debug_script::wait_for_debugger(device_t &device, bool firststop)
{
	// called over and over while the machine is stopped: let Lua look, and do not spin
	emulator_info::periodic_check();
	osd_sleep(osd_ticks_per_second() / 1000);
}

} // anonymous namespace

} // namespace osd

MODULE_DEFINITION(DEBUG_SCRIPT, osd::debug_script)
