#!/usr/bin/env bash
#
# mayhem/test.sh — run upstream's own catch2 suite (Code/tests: encoding round-trips of client and
# server messages through the factories, the string cache, and the client playback clock), built by
# mayhem/build.sh with normal flags. The tests assert decoded field values, so a no-op binary fails.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"
# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER="$SRC/mayhem/build/test/TPTests"
if [ ! -x "$RUNNER" ]; then
  echo "test.sh: $RUNNER missing — mayhem/build.sh must build it" >&2
  emit_ctrf "catch2" 0 1 0
  exit 1
fi

out=$("$RUNNER" 2>&1); rc=$?
echo "$out"
# Catch2 v2 summary: "All tests passed (A assertions in N test cases)" or
# "test cases: N | P passed | F failed"
passed=0; failed=0
if line=$(grep -E '^All tests passed \([0-9]+ assertions? in [0-9]+ test cases?\)' <<<"$out"); then
  passed=$(sed -E 's/.* in ([0-9]+) test case.*/\1/' <<<"$line")
elif line=$(grep -E '^test cases:' <<<"$out"); then
  passed=$(grep -oE '[0-9]+ passed' <<<"$line" | grep -oE '[0-9]+' || echo 0)
  failed=$(grep -oE '[0-9]+ failed' <<<"$line" | grep -oE '[0-9]+' || echo 0)
fi
# No summary at all (runner neutered/crashed) or a non-zero exit is a failure.
if [ "$passed" -eq 0 ] && [ "$failed" -eq 0 ]; then failed=1; fi
if [ "$rc" -ne 0 ] && [ "$failed" -eq 0 ]; then failed=1; fi
emit_ctrf "catch2" "$passed" "$failed" 0
