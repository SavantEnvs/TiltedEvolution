// Fuzz the server message decoder: ServerMessageFactory::Extract, the entry point that turns one
// network packet into a message (byte 0 = opcode, then that message's DeserializeRaw/Differential).
// This is what a client does with every packet a (possibly malicious) server sends it.
// A decoded message is re-serialized, as the receiving side would forward/echo it.
#include <EncodingPch.h>
#include <Messages/ServerMessageFactory.h>
#include <StringCache.h>
#include <TiltedCore/StandardAllocator.hpp>
#include <TiltedCore/ViewBuffer.hpp>

#include <cstdint>
#include <cstddef>

using namespace TiltedPhoques;

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
    // TiltedCore defaults to mimalloc, which ASan cannot see into; route this thread's message
    // allocations through malloc so heap overflows in the decoders are detected.
    static StandardAllocator s_allocator;
    Allocator::Set(&s_allocator);

    // CachedString (de)serialization writes every string into the process-global StringCache
    // (AddWanted) and resolves cached ids against it; start each input from an empty cache so its
    // result depends only on that input.
    StringCache::Get().Clear();

    ViewBuffer buf(const_cast<uint8_t*>(data), size);
    Buffer::Reader reader(&buf);

    const ServerMessageFactory factory;
    auto pMessage = factory.Extract(reader);
    if (!pMessage)
        return 0;

    Buffer out(1 << 20);
    Buffer::Writer writer(&out);
    pMessage->Serialize(writer);
    return 0;
}
