#!/usr/bin/env bash
#
# mayhem/build.sh — build automerge-rs's cargo-fuzz target (`load`, upstream's own
# rust/automerge/fuzz crate) as a sanitized libFuzzer binary, then pre-build the
# upstream Rust test suite (normal flags) so mayhem/test.sh only RUNS it.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
# This first (online) build populates the cargo registry under $CARGO_HOME; the
# offline re-run resolves crates from that cache (CARGO_NET_OFFLINE=true is set
# by the rlenv runtime — do NOT hard-code --offline here).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# Two fuzz crates: upstream's own rust/automerge/fuzz (`load`), plus the additive
# mayhem/fuzz crate carrying the historical decode_state / load_incremental harnesses.
FUZZ_DIRS=("rust/automerge/fuzz" "mayhem/fuzz")
TRIPLE="x86_64-unknown-linux-gnu"

# Debug-info contract (§6.2 item 10): DWARF < 4 on the fuzz binaries. clang's
# $SANITIZER_FLAGS are C flags rustc ignores — Rust ASan comes via -Zsanitizer=address
# below (the Rust equivalent of $SANITIZER_FLAGS), and DWARF-3 via -Zdwarf-version.
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C dwarf-version=3}"

SAVED_RUSTFLAGS="${RUSTFLAGS:-}"
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address $RUST_DEBUG_FLAGS"
# libfuzzer-sys compiles the C++ libFuzzer runtime via the cc crate; clang's plain
# -g emits DWARF-5, so pin those objects to DWARF-3 too.
SAVED_CFLAGS="${CFLAGS:-}"; SAVED_CXXFLAGS="${CXXFLAGS:-}"
export CFLAGS="${CFLAGS:-} -gdwarf-3" CXXFLAGS="${CXXFLAGS:-} -gdwarf-3"

# The prebuilt ASan runtime archive ships DWARF-5 CUs and lands first in the link;
# prepend a clang -gdwarf-3 anchor object via a -Clinker wrapper so the CU at
# offset 0 of .debug_info is DWARF-3 (netnew-fleet-playbook §6, rust-dwarf recipe).
ANCHOR_DIR=/tmp/dwarf-anchor
mkdir -p "$ANCHOR_DIR"
echo 'int mayhem_dwarf_anchor(void){return 0;}' > "$ANCHOR_DIR/anchor.c"
clang -gdwarf-3 -c "$ANCHOR_DIR/anchor.c" -o "$ANCHOR_DIR/anchor.o"
printf '#!/bin/sh\nexec clang %s/anchor.o "$@"\n' "$ANCHOR_DIR" > "$ANCHOR_DIR/cc-wrapper.sh"
chmod +x "$ANCHOR_DIR/cc-wrapper.sh"
export RUSTFLAGS="$RUSTFLAGS -Clinker=$ANCHOR_DIR/cc-wrapper.sh"

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"

for FUZZ_DIR in "${FUZZ_DIRS[@]}"; do
  FUZZ_TARGETS=()
  for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
    FUZZ_TARGETS+=("$(basename "${f%.*}")")
  done
  [ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

  for t in "${FUZZ_TARGETS[@]}"; do
    echo "--- building fuzz target: $t ($FUZZ_DIR) ---"
    cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
    bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
    [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
    cp "$bin" "/mayhem/$t"
    echo "built /mayhem/$t"
  done
done

# ── Pre-build the upstream test suite with the project's NORMAL flags ─────────
# Mirrors upstream CI (scripts/ci/build-test): the whole Rust suite. test.sh
# only RUNS these pre-built tests (cargo test finds them up to date, offline).
export RUSTFLAGS="$SAVED_RUSTFLAGS" CFLAGS="$SAVED_CFLAGS" CXXFLAGS="$SAVED_CXXFLAGS"
echo "=== pre-building upstream test suite (scripts/ci/build-test set) ==="
cd "$SRC/rust"
cargo test --no-run -p automerge --features slow_path_assertions
cargo test --no-run -p automerge-test
cargo test --no-run -p automerge-c
cargo test --no-run -p automerge-cli
cargo test --no-run -p automerge-wasm

echo "build.sh complete"
