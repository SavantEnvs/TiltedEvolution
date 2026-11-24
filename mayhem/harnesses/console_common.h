// Shared set-up for the console harnesses.
//
// ConsoleRegistry links every Command/Setting it creates into a process-global intrusive list
// (CommandBase::ROOT / SettingBase::ROOT, consumed by the NEXT registry's BindStaticItems) and its
// destructor does not unlink them, so a registry destroyed and re-created per input would walk freed
// memory. The server builds exactly one registry for the process lifetime; the harnesses do the same,
// and reset every setting to its default before each input so an input's result depends on that
// input alone (a /set or an INI value from a previous input never leaks into the next).
#pragma once

#include <console/ConsoleRegistry.h>
#include <console/Setting.h>
#include <spdlog/spdlog.h>
#include <spdlog/sinks/null_sink.h>

#include <cstdint>
#include <memory>

namespace fuzz_console
{
inline Console::ConsoleRegistry& Registry()
{
    static Console::ConsoleRegistry* s_reg = []
    {
        // Logging is process-global and never changed by an input; a null sink keeps the fuzzer fast.
        spdlog::set_level(spdlog::level::off);
        spdlog::register_logger(std::make_shared<spdlog::logger>("fuzz", std::make_shared<spdlog::sinks::null_sink_mt>()));
        auto* reg = new Console::ConsoleRegistry("fuzz");
        // One setting of every type the console and the INI loader convert (names as in STServer.ini).
        reg->RegisterSetting<bool>("GameServer:bPremiumMode", "bool", true);
        reg->RegisterSetting<int32_t>("GameServer:iTickRate", "int", 60);
        reg->RegisterSetting<uint32_t>("GameServer:uPort", "uint", 10578);
        reg->RegisterSetting<int64_t>("GameServer:lBig", "int64", -5);
        reg->RegisterSetting<uint64_t>("GameServer:ulBig", "uint64", 5);
        reg->RegisterSetting<float>("Gameplay:fDifficulty", "float", 1.0f);
        reg->RegisterSetting("GameServer:sServerName", "string", "Server");
        reg->RegisterSetting("GameServer:sPassword", "string", "");
        return reg;
    }();
    return *s_reg;
}

inline void ResetSettings(Console::ConsoleRegistry& aReg)
{
    auto* s = aReg.FindSetting("GameServer:bPremiumMode");  s->data.as_boolean = true;
    s = aReg.FindSetting("GameServer:iTickRate");           s->data.as_int32 = 60;
    s = aReg.FindSetting("GameServer:uPort");               s->data.as_uint32 = 10578;
    s = aReg.FindSetting("GameServer:lBig");                s->data.as_int64 = -5;
    s = aReg.FindSetting("GameServer:ulBig");               s->data.as_uint64 = 5;
    s = aReg.FindSetting("Gameplay:fDifficulty");           s->data.as_float = 1.0f;
    s = aReg.FindSetting("GameServer:sServerName");
    static_cast<Console::StringSetting*>(s)->StoreValue(*s, "Server");
    s = aReg.FindSetting("GameServer:sPassword");
    static_cast<Console::StringSetting*>(s)->StoreValue(*s, "");
}
} // namespace fuzz_console
