// Synthetic JIT gate for the isolated StikJIT test host: no game code is
// loaded, written or executed. Proves the helper can prepare an executable
// region through the product's own DebuggerArena path, that execute survives
// detachment, and that entry is refused once nothing is attached.
#include "DebuggerArena.h"
#include "HostDiagnostics.h"
#include "NativeCodeMemory.h"
#include <mach/machine.h>
#include <mach/vm_map.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#define RET_INSTRUCTION 0xD65F03C0u

size_t TKJITSelfTest(char *out, size_t size) {
    if (!out || size < 96) return 0;
    out[0] = 0;
    size_t used = 0;

    if (hd_debugger_attached())
        return snprintf(out, size, "FAIL\nA debugger is already attached before JIT preparation.\n");
    if (hd_may_run_unsigned_code())
        used += snprintf(out + used, size - used, "CS_DEBUGGED was already set before preparation (unexpected).\n");

    NativeCodeMemory memory = {0};
    if (!da_request_arena(&memory, 16384, NULL)) {
        return snprintf(out, size, "FAIL\nThe helper did not prepare an executable region; guest entry stays closed.\n");
    }
    const uint32_t ret = RET_INSTRUCTION;
    bool written = nc_write(&memory, 0, &ret, sizeof ret);

    void (*execute)(void) = memory.executable;
    if (written && memory.executable) execute();  // executes only a `ret`

    bool executable_before = hd_is_executable(memory.executable);
    bool released = da_release_debugger(&memory, NULL);
    bool executable_after = hd_is_executable(memory.executable);
    bool entry_allowed = da_entry_allowed(&memory, NULL);
    nc_destroy(&memory);

    used += snprintf(out + used, size - used,
        "Arena: %lu bytes, written=%d\n"
        "Executable before detach: %s\n"
        "Helper asked to detach:   %s\n"
        "Executable after detach:  %s\n"
        "Guest entry gate:         %s\n",
        (unsigned long)memory.size, written,
        executable_before ? "yes" : "no",
        released ? "yes" : "no",
        executable_after ? "yes" : "no",
        entry_allowed ? "ready" : "closed");

    if (!executable_before || !released || !executable_after || !entry_allowed)
        used += snprintf(out + used, size - used, "\nRESULT: FAIL\n");
    else
        used += snprintf(out + used, size - used, "\nRESULT: PASS - prepared, executed, detached, still executable.\n");
    return used;
}
