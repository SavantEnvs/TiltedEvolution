// Fuzz the Bethesda plugin (ESM/ESP/ESL) loader the dedicated server runs on every plugin in its
// load order (ESLoader::BuildRecordCollection): TESFile::LoadFile reads the file, IndexRecords walks
// its GRUP/record tree, inflates compressed records (zlib) and parses TES4/REFR/CLMT/NPC_/CONT/GMST/
// WRLD/NAVM records into a RecordCollection.
#include <ESLoader.h>
#include <TESFile.h>
#include <RecordCollection.h>
#include <TiltedCore/StandardAllocator.hpp>
#include <spdlog/spdlog.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <unistd.h>

using namespace TiltedPhoques;

static std::string s_path;

extern "C" int LLVMFuzzerInitialize(int*, char***)
{
    // Logging is process-global and not input-controlled; silence it so the fuzzer isn't I/O bound.
    spdlog::set_level(spdlog::level::off);
    const char* tmp = getenv("TMPDIR");
    std::string dir = (tmp && *tmp) ? tmp : "/tmp";
    std::string templ = dir + "/fuzz_esm_XXXXXX";
    if (!mkdtemp(templ.data()))
        abort();
    // TESFile takes a path; the loader names plugins *.esm/*.esp/*.esl.
    s_path = templ + "/fuzz.esm";
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
    // Format precondition: a plugin file starts with its TES4 record header (type, data size, flags,
    // form id, version control, form version: 24 bytes, ESLoader's `Record` layout in
    // Records/Record.h), which IndexRecords reads unconditionally. Shorter files are not plugins.
    // The same unchecked header read stays reachable through a truncated record anywhere after the
    // first one, so this hides no code path.
    if (size < 24)
        return -1;

    // TiltedCore defaults to mimalloc, which ASan cannot see into; use malloc instead.
    static StandardAllocator s_allocator;
    Allocator::Set(&s_allocator);

    FILE* f = fopen(s_path.c_str(), "wb");
    if (!f)
        abort();
    if (size && fwrite(data, 1, size, f) != size)
        abort();
    fclose(f);

    Map<String, uint8_t> masters;
    ESLoader::TESFile file(masters);
    file.Setup(static_cast<uint8_t>(0));
    if (file.LoadFile(s_path))
    {
        ESLoader::RecordCollection collection;
        file.IndexRecords(collection);
    }
    return 0;
}
