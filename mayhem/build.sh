#!/usr/bin/env bash
#
# mayhem/build.sh — TiltedEvolution. Upstream's xmake build downloads its packages, so this compiles
# the network-message encoding library (Code/encoding, + TiltedCore's Buffer/Serialization it reads
# with) directly against the pinned deps cached in /opt/toolchains/deps (see mayhem/Dockerfile):
#   1. fuzz build: encoding + TiltedCore with $SANITIZER_FLAGS $DEBUG_FLAGS -> two libFuzzer harnesses
#      (+ -standalone reproducers) in /mayhem;
#   2. test build: the same sources with normal flags + upstream's catch2 suite (Code/tests) ->
#      mayhem/build/test/TPTests, which mayhem/test.sh runs.
# Re-runnable and offline: it only reads the checkout and /opt/toolchains/deps.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

DEPS=/opt/toolchains/deps
TC=$DEPS/tiltedcore-0.2.9
MI=$DEPS/mimalloc-2.2.4
cd "$SRC"

INCLUDES="-I$SRC/Code/encoding -I$SRC/Code -I$SRC/Code/encoding/Structs/Skyrim \
 -I$TC/include -I$TC/src/Code/core/include -I$DEPS/hopscotch-map-2.3.1/include \
 -I$DEPS/glm-0.9.9.8/include -I$MI/include"
ENC_FLAGS="-std=c++20 -include $SRC/Code/encoding/EncodingPch.h $INCLUDES"
TC_FLAGS="-std=c++20 -I$TC/src/Code/core/include -I$DEPS/hopscotch-map-2.3.1/include -I$MI/include"

# compile_set <outdir> <cxxflags...>: compile encoding + TiltedCore sources into <outdir>/*.o
compile_set() {
  local out="$1"; shift
  local flags="$*"
  mkdir -p "$out"
  {
    find Code/encoding -name '*.cpp' | sort | sed "s|^|ENC |"
    find "$TC/src/Code/core/src" -name '*.cpp' | sort | sed "s|^|TC |"
  } | while read -r kind f; do
    o="$out/$(echo "${f#$SRC/}" | tr '/' '_' | sed 's/\.cpp$/.o/')"
    printf '%s\t%s\t%s\n' "$kind" "$f" "$o"
  done > "$out/objects.lst"
  export ENC_FLAGS TC_FLAGS flags
  cut -f1-3 "$out/objects.lst" | tr '\t' ' ' | xargs -P "$MAYHEM_JOBS" -n 3 sh -c '
    if [ "$0" = ENC ]; then extra="$ENC_FLAGS"; else extra="$TC_FLAGS"; fi
    $CXX $flags $extra -c "$1" -o "$2"' 
  cut -f3 "$out/objects.lst" | xargs ar rcs "$out/libencoding.a.tmp"
  mv -f "$out/libencoding.a.tmp" "$out/libencoding.a"
}

# 1) Fuzz build. Objects get SanCov (fuzzer-no-link) so libFuzzer/Mayhem see their edges; with an
#    empty SANITIZER_FLAGS (no-sanitizer build) only the harness links -fsanitize=fuzzer.
COV_FLAGS="-fsanitize=fuzzer-no-link"
FUZZ_OUT=mayhem/build/fuzz
rm -f "$FUZZ_OUT/libencoding.a"
compile_set "$FUZZ_OUT" "$SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS -O1"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$FUZZ_OUT/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$FUZZ_OUT/standalone_main.o"
for h in fuzz_client_messages fuzz_server_messages; do
  $CXX $SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS -O1 $ENC_FLAGS -c "mayhem/harnesses/$h.cpp" -o "$FUZZ_OUT/$h.o"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$FUZZ_OUT/$h.o" "$FUZZ_OUT/lsan_off.o" \
    "$FUZZ_OUT/libencoding.a" "$MI/lib/libmimalloc.a" -lpthread -o "$SRC/$h"
  $CXX $SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS "$FUZZ_OUT/$h.o" "$FUZZ_OUT/standalone_main.o" "$FUZZ_OUT/lsan_off.o" \
    "$FUZZ_OUT/libencoding.a" "$MI/lib/libmimalloc.a" -lpthread -o "$SRC/$h-standalone"
done

# 1b) ESM/ESP/ESL plugin loader (Code/components/es_loader), the server's Bethesda plugin parser.
ES_FLAGS="-std=c++20 -include $SRC/Code/components/es_loader/stdafx.h -I$SRC/Code/components/es_loader \
 -I$SRC/Code/components -I$SRC/Code -I$SRC -I$TC/include -I$TC/src/Code/core/include \
 -I$DEPS/hopscotch-map-2.3.1/include -I$DEPS/glm-0.9.9.8/include -I$DEPS/spdlog-1.13.0/include -I$MI/include"
# The loader casts Record*/Chunk* straight onto file offsets; records in real plugins have odd sizes, so
# UBSan's `alignment` check fires on every valid plugin (benign on x86). Relax only that check, only
# for the loader; ASan and the rest of UBSan stay halting.
ES_FLAGS="$ES_FLAGS -fno-sanitize=alignment"
ES_OUT=$FUZZ_OUT/es_loader
mkdir -p "$ES_OUT"
export ES_FLAGS ES_OUT COV_FLAGS
find Code/components/es_loader -name '*.cpp' ! -name '*Test.cpp' | sort | xargs -P "$MAYHEM_JOBS" -n 1 sh -c '
  $CXX $SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS -O1 $ES_FLAGS -c "$0" -o "$ES_OUT/$(echo "$0" | tr / _ | sed "s/\.cpp\$/.o/")"'
ES_OBJS=$(find "$ES_OUT" -name '*.o' | sort)
h=fuzz_esm_loader
$CXX $SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS -O1 $ES_FLAGS -c "mayhem/harnesses/$h.cpp" -o "$FUZZ_OUT/$h.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$FUZZ_OUT/$h.o" "$FUZZ_OUT/lsan_off.o" $ES_OBJS \
  "$FUZZ_OUT/libencoding.a" "$MI/lib/libmimalloc.a" -lz -lpthread -o "$SRC/$h"
$CXX $SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS "$FUZZ_OUT/$h.o" "$FUZZ_OUT/standalone_main.o" "$FUZZ_OUT/lsan_off.o" $ES_OBJS \
  "$FUZZ_OUT/libencoding.a" "$MI/lib/libmimalloc.a" -lz -lpthread -o "$SRC/$h-standalone"

# 1c) Server console (Code/components/console: command line parser + STServer.ini settings loader)
#     with the SimpleIni it parses INI files with (Code/base/simpleini).
CON_FLAGS="-std=c++20 -I$SRC/Code/components -I$SRC/Code -I$SRC -I$TC/include -I$TC/src/Code/core/include \
 -I$DEPS/hopscotch-map-2.3.1/include -I$DEPS/glm-0.9.9.8/include -I$DEPS/spdlog-1.13.0/include -I$MI/include"
CON_OUT=$FUZZ_OUT/console
mkdir -p "$CON_OUT"
export CON_FLAGS CON_OUT
{ find Code/components/console -name '*.cpp' ! -name '*Test.cpp'; echo Code/base/simpleini/ConvertUTF.cpp; } | sort | \
  xargs -P "$MAYHEM_JOBS" -n 1 sh -c '
  $CXX $SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS -O1 $CON_FLAGS -c "$0" -o "$CON_OUT/$(echo "$0" | tr / _ | sed "s/\.cpp\$/.o/")"'
CON_OBJS=$(find "$CON_OUT" -name '*.o' | sort)
for h in fuzz_console_command fuzz_ini_settings; do
  $CXX $SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS -O1 $CON_FLAGS -c "mayhem/harnesses/$h.cpp" -o "$FUZZ_OUT/$h.o"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$FUZZ_OUT/$h.o" "$FUZZ_OUT/lsan_off.o" $CON_OBJS \
    "$FUZZ_OUT/libencoding.a" "$MI/lib/libmimalloc.a" -lpthread -o "$SRC/$h"
  $CXX $SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS "$FUZZ_OUT/$h.o" "$FUZZ_OUT/standalone_main.o" "$FUZZ_OUT/lsan_off.o" $CON_OBJS \
    "$FUZZ_OUT/libencoding.a" "$MI/lib/libmimalloc.a" -lpthread -o "$SRC/$h-standalone"
done

# 1d) Resource manifests (Code/components/resources): ResourceCollection's start-up scan, which parses
#     every resources/<package>/*.manifest with SimpleIni + SemanticVersion and resolves dependencies.
RES_FLAGS="$CON_FLAGS -I$SRC/Code/components/resources"
RES_OUT=$FUZZ_OUT/resources
mkdir -p "$RES_OUT"
$CXX $SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS -O1 $RES_FLAGS -c Code/components/resources/ResourceCollection.cpp \
  -o "$RES_OUT/ResourceCollection.o"
RES_OBJS="$RES_OUT/ResourceCollection.o $CON_OUT/Code_base_simpleini_ConvertUTF.o"
h=fuzz_resource_manifest
$CXX $SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS -O1 $RES_FLAGS -c "mayhem/harnesses/$h.cpp" -o "$FUZZ_OUT/$h.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$FUZZ_OUT/$h.o" "$FUZZ_OUT/lsan_off.o" $RES_OBJS \
  "$FUZZ_OUT/libencoding.a" "$MI/lib/libmimalloc.a" -lpthread -o "$SRC/$h"
$CXX $SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS "$FUZZ_OUT/$h.o" "$FUZZ_OUT/standalone_main.o" "$FUZZ_OUT/lsan_off.o" $RES_OBJS \
  "$FUZZ_OUT/libencoding.a" "$MI/lib/libmimalloc.a" -lpthread -o "$SRC/$h-standalone"

# 2) Test build (normal flags): upstream's TPTests catch2 suite (Code/tests/xmake.lua).
TEST_OUT=mayhem/build/test
rm -f "$TEST_OUT/libencoding.a"
compile_set "$TEST_OUT" "-O1 $COVERAGE_FLAGS"
TEST_OBJS=(); PIDS=()
for f in Code/tests/main.cpp Code/tests/encoding.cpp Code/tests/playback_clock.cpp Code/client/Systems/PlaybackClock.cpp; do
  o="$TEST_OUT/test_$(echo "$f" | tr '/' '_' | sed 's/\.cpp$/.o/')"
  $CXX -O1 $COVERAGE_FLAGS $ENC_FLAGS -I$SRC/Code/tests -I$DEPS/catch2-2.13.10/include -c "$f" -o "$o" &
  PIDS+=($!); TEST_OBJS+=("$o")
done
for p in "${PIDS[@]}"; do wait "$p"; done
$CXX $COVERAGE_FLAGS "${TEST_OBJS[@]}" "$TEST_OUT/libencoding.a" "$MI/lib/libmimalloc.a" -lpthread -o "$TEST_OUT/TPTests"
echo "build.sh: done"
