# syntax=docker/dockerfile:1.7
#
# Commit image for TiltedEvolution (Skyrim Together Reborn). Upstream builds with xmake, which
# downloads its packages at build time; mayhem/build.sh instead compiles the network-message
# encoding library (Code/encoding) and its deps directly, from the pinned sources cached below.
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# Upstream's xmake package set, pinned to the versions its xmake.lua requires (SPEC §6.2 item 19).
# Header-only libs (hopscotch-map, glm, spdlog used header-only, catch2 v2): src/ + include/. TiltedCore (the bitstream reader the deserializers use) is
# itself part of the fuzzed surface, so build.sh compiles it from src/ with the fuzz flags.
# mimalloc is built here, uninstrumented, as a static lib (TiltedCore's default allocator).
USER root
ARG TILTEDCORE_SHA256=60ecd4e79c7543bc0c228f8a7200cc242c03a5d88764a3e8c0b97d02b010f477
ARG HOPSCOTCH_SHA256=53dab49005cd5dc859f2546d0d3eef058ec7fb3b74fc3b19f4965a9a151e9b20
ARG GLM_SHA256=7d508ab72cb5d43227a3711420f06ff99b0a0cb63ee2f93631b162bfe1fe9592
ARG MIMALLOC_SHA256=754a98de5e2912fddbeaf24830f982b4540992f1bab4a0a8796ee118e0752bda
ARG SPDLOG_SHA256=534f2ee1a4dcbeb22249856edfb2be76a1cf4f708a20b0ac2ed090ee24cfdbc9
ARG CATCH2_SHA256=3725c0f0a75f376a5005dde31ead0feb8f7da7507644c201b814443de8355170
RUN set -eux; D=/opt/toolchains/deps; fetch() { curl -fsSL -o "$3" "$1" && echo "$2  $3" | sha256sum -c -; }; \
    fetch https://github.com/tiltedphoques/TiltedCore/archive/refs/tags/v0.2.9.tar.gz "$TILTEDCORE_SHA256" /tmp/tc.tgz; \
    mkdir -p $D/tiltedcore-0.2.9/src $D/tiltedcore-0.2.9/include; tar -xzf /tmp/tc.tgz --strip-components=1 -C $D/tiltedcore-0.2.9/src; \
    ln -s ../src/Code/core/include $D/tiltedcore-0.2.9/include/TiltedCore; \
    fetch https://github.com/Tessil/hopscotch-map/archive/refs/tags/v2.3.1.tar.gz "$HOPSCOTCH_SHA256" /tmp/hm.tgz; \
    mkdir -p $D/hopscotch-map-2.3.1/src; tar -xzf /tmp/hm.tgz --strip-components=1 -C $D/hopscotch-map-2.3.1/src; \
    ln -s src/include $D/hopscotch-map-2.3.1/include; \
    fetch https://github.com/g-truc/glm/archive/refs/tags/0.9.9.8.tar.gz "$GLM_SHA256" /tmp/glm.tgz; \
    mkdir -p $D/glm-0.9.9.8/src $D/glm-0.9.9.8/include; tar -xzf /tmp/glm.tgz --strip-components=1 -C $D/glm-0.9.9.8/src; \
    ln -s ../src/glm $D/glm-0.9.9.8/include/glm; \
    fetch https://github.com/gabime/spdlog/archive/refs/tags/v1.13.0.tar.gz "$SPDLOG_SHA256" /tmp/spdlog.tgz; \
    mkdir -p $D/spdlog-1.13.0/src; tar -xzf /tmp/spdlog.tgz --strip-components=1 -C $D/spdlog-1.13.0/src; \
    ln -s src/include $D/spdlog-1.13.0/include; \
    fetch https://github.com/catchorg/Catch2/releases/download/v2.13.10/catch.hpp "$CATCH2_SHA256" /tmp/catch.hpp; \
    mkdir -p $D/catch2-2.13.10/src $D/catch2-2.13.10/include/catch2; cp /tmp/catch.hpp $D/catch2-2.13.10/src/; \
    ln -s ../../src/catch.hpp $D/catch2-2.13.10/include/catch2/catch.hpp; \
    fetch https://github.com/microsoft/mimalloc/archive/refs/tags/v2.2.4.tar.gz "$MIMALLOC_SHA256" /tmp/mi.tgz; \
    M=$D/mimalloc-2.2.4; mkdir -p $M/src $M/lib /tmp/mi-build; tar -xzf /tmp/mi.tgz --strip-components=1 -C $M/src; \
    ln -s src/include $M/include; \
    clang -O2 -g -gdwarf-3 -fPIC -I$M/src/include -c $M/src/src/static.c -o /tmp/mi-build/mimalloc.o; \
    ar rcs $M/lib/libmimalloc.a /tmp/mi-build/mimalloc.o; \
    rm -rf /tmp/*.tgz /tmp/catch.hpp /tmp/mi-build; chmod -R a+rX $D
USER mayhem

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
