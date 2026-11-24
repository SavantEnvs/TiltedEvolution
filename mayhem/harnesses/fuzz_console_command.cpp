// Fuzz the server console/admin command line: Console::ConsoleRegistry::TryExecuteCommand
// (StringTokenizer, command lookup, argument-count check, typed argument conversion in
// ConsoleUtils) followed by Update(), which runs the queued command. This is the path a
// remote admin's command line takes on the dedicated server (GameServer admin sessions).
#include "console_common.h"
#include <TiltedCore/StandardAllocator.hpp>

#include <cstdint>
#include <cstddef>

using namespace TiltedPhoques;

static volatile uint64_t s_sink = 0;

extern "C" int LLVMFuzzerInitialize(int*, char***)
{
    static StandardAllocator s_allocator; // ASan can't see into TiltedCore's default mimalloc
    Allocator::Set(&s_allocator);
    auto& reg = fuzz_console::Registry();
    // Commands with each argument type the registry converts (CreateArgStack pushes numerics as
    // int64_t, booleans as bool and strings as TiltedPhoques::String; the handlers pop exactly those,
    // like the server's own commands). Their handlers keep no state.
    reg.RegisterCommand<int64_t, bool>("ib", "int bool", [](Console::ArgStack& s) { s_sink = s_sink + static_cast<uint64_t>(s.Pop<int64_t>()); s_sink = s_sink + static_cast<uint64_t>(s.Pop<bool>()); });
    reg.RegisterCommand<const char*>("str", "string", [](Console::ArgStack& s) { s_sink = s_sink + static_cast<uint64_t>(s.Pop<String>().size()); });
    reg.RegisterCommand<int64_t, const char*, int64_t>("isi", "int string int", [](Console::ArgStack& s) { s_sink = s_sink + static_cast<uint64_t>(s.Pop<int64_t>()); s_sink = s_sink + static_cast<uint64_t>(s.Pop<String>().size()); s_sink = s_sink + static_cast<uint64_t>(s.Pop<int64_t>()); });
    reg.RegisterCommand<>("noargs", "no args", [](Console::ArgStack&) { s_sink = s_sink + static_cast<uint64_t>(1); });
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
    auto& reg = fuzz_console::Registry();
    fuzz_console::ResetSettings(reg);
    reg.TryExecuteCommand(String(reinterpret_cast<const char*>(data), size));
    reg.Update(); // runs the queued command (and drains the queue)
    return 0;
}
