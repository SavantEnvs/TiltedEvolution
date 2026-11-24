// Fuzz the server's settings-file loader: Console::LoadSettingsFromIni (STServer.ini) parses the
// file with SimpleIni (Code/base/simpleini) and converts each registered setting's value (bool,
// int, uint, int64, uint64, float, string), then SaveSettingsToIni writes the result back out,
// as the server does on start-up.
#include "console_common.h"
#include <console/IniSettingsProvider.h>
#include <TiltedCore/StandardAllocator.hpp>
#include <spdlog/spdlog.h>
#include <spdlog/sinks/null_sink.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <unistd.h>

using namespace TiltedPhoques;

static std::string s_in, s_out;

extern "C" int LLVMFuzzerInitialize(int*, char***)
{
    static StandardAllocator s_allocator; // ASan can't see into TiltedCore's default mimalloc
    Allocator::Set(&s_allocator);
    fuzz_console::Registry();
    const char* tmp = getenv("TMPDIR");
    std::string templ = std::string((tmp && *tmp) ? tmp : "/tmp") + "/fuzz_ini_XXXXXX";
    if (!mkdtemp(templ.data()))
        abort();
    s_in = templ + "/STServer.ini";
    s_out = templ + "/STServer.out.ini";
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
    FILE* f = fopen(s_in.c_str(), "wb");
    if (!f)
        abort();
    if (size && fwrite(data, 1, size, f) != size)
        abort();
    fclose(f);

    auto& reg = fuzz_console::Registry();
    fuzz_console::ResetSettings(reg);

    Console::LoadSettingsFromIni(reg, s_in);
    Console::SaveSettingsToIni(reg, s_out);
    return 0;
}
