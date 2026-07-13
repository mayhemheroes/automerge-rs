#!/usr/bin/env bash
#
# mayhem/test.sh — RUN upstream's Rust test suite (the scripts/ci/build-test set:
# cargo test for automerge [slow_path_assertions], automerge-test, automerge-c,
# automerge-cli, automerge-wasm). The suite was pre-built by mayhem/build.sh with
# the project's normal flags; this script only runs it and reports CTRF counts.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"
cd "$SRC"

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

cd "$SRC/rust"

LOG="$(mktemp)"
run_suite() {
  # cargo test prints one "test result: ok|FAILED. P passed; F failed; I ignored; ..." per test binary
  RUST_LOG=error cargo test "$@" 2>&1 | tee -a "$LOG"
  return "${PIPESTATUS[0]}"
}

overall_rc=0
run_suite -p automerge --features slow_path_assertions || overall_rc=1
run_suite -p automerge-test                            || overall_rc=1
run_suite -p automerge-c                               || overall_rc=1
run_suite -p automerge-cli                             || overall_rc=1
run_suite -p automerge-wasm                            || overall_rc=1

PASSED=0; FAILED=0; SKIPPED=0
while IFS= read -r line; do
  p="$(sed -nE 's/.*test result: [^.]*\. ([0-9]+) passed.*/\1/p' <<<"$line")"
  f="$(sed -nE 's/.*test result: [^.]*\. [0-9]+ passed; ([0-9]+) failed.*/\1/p' <<<"$line")"
  i="$(sed -nE 's/.*test result: [^.]*\. [0-9]+ passed; [0-9]+ failed; ([0-9]+) ignored.*/\1/p' <<<"$line")"
  PASSED=$(( PASSED + ${p:-0} )); FAILED=$(( FAILED + ${f:-0} )); SKIPPED=$(( SKIPPED + ${i:-0} ))
done < <(grep -E 'test result:' "$LOG")

# A suite invocation that died before printing results (build/run error) must fail loudly.
if [ "$overall_rc" -ne 0 ] && [ "$FAILED" -eq 0 ]; then FAILED=1; fi
if [ "$PASSED" -eq 0 ]; then echo "ERROR: no tests ran — build.sh should have pre-built the suite" >&2; FAILED=$(( FAILED + 1 )); fi

emit_ctrf "cargo-test" "$PASSED" "$FAILED" "$SKIPPED"
