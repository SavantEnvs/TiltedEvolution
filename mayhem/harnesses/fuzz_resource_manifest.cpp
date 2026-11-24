// Fuzz the server's resource-manifest loader: Resources::ResourceCollection's constructor is what the
// server runs at start-up (CollectResources): it scans ./resources/<package>/*.manifest, parses each
// file with SimpleIni (LoadManifestData: semantic versions, quoted string lists, `name@x.y.z`
// dependency specs -> SemanticVersion), resolves dependencies between the loaded manifests and drops
// the broken ones. Resource packages are third-party downloads, so their manifests are untrusted.
//
// The input is split on NUL bytes into up to kMaxManifests manifest files, one per package folder,
// so dependency resolution between several manifests is reachable.
#include <ResourceCollection.h>
#include <TiltedCore/StandardAllocator.hpp>
#include <spdlog/spdlog.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <unistd.h>

using namespace TiltedPhoques;
namespace fs = std::filesystem;

static constexpr size_t kMaxManifests = 4;
static fs::path s_resources;

extern "C" int LLVMFuzzerInitialize(int*, char***)
{
    static StandardAllocator s_allocator; // ASan can't see into TiltedCore's default mimalloc
    Allocator::Set(&s_allocator);
    // CollectResources reads `current_path()/resources`: run from a private scratch directory.
    const char* tmp = getenv("TMPDIR");
    std::string templ = std::string((tmp && *tmp) ? tmp : "/tmp") + "/fuzz_manifest_XXXXXX";
    if (!mkdtemp(templ.data()) || chdir(templ.c_str()) != 0)
        abort();
    s_resources = fs::path(templ) / "resources";
    // Logging is a constant process-wide setting; turned off only to keep the fuzzer's output quiet.
    spdlog::set_level(spdlog::level::off);
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
    // Each input starts from an empty resources/ folder holding only its own manifests.
    std::error_code ec;
    fs::remove_all(s_resources, ec);
    fs::create_directories(s_resources);

    size_t start = 0;
    for (size_t i = 0; i < kMaxManifests && start <= size; ++i)
    {
        size_t end = start;
        while (end < size && data[end] != 0)
            ++end;
        if (i + 1 == kMaxManifests)
            end = size; // the last manifest takes the rest, NULs included
        const fs::path dir = s_resources / ("pkg" + std::to_string(i));
        fs::create_directory(dir);
        FILE* f = fopen((dir / "resource.manifest").c_str(), "wb");
        if (!f)
            abort();
        if (end > start && fwrite(data + start, 1, end - start, f) != end - start)
            abort();
        fclose(f);
        start = end + 1;
    }

    Resources::ResourceCollection collection;
    size_t total = 0;
    collection.ForEachManifest([&](const Resources::Manifest001& m) { total += m.Name.size() + m.Dependencies.size(); });
    return 0;
}
