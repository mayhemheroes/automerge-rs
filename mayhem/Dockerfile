# Build Stage
FROM ubuntu:22.04 as builder

RUN apt-get update && apt-get install -y curl build-essential
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly
ENV PATH=/root/.cargo/bin:/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin:/opt/pmk/env/global/bin:/Users/rizaziz/.local/bin
RUN cargo install cargo-fuzz

## Add source code to the build stage.
ADD . /src
WORKDIR /src

RUN echo building instrumented harnesses &&     bash -c "pushd automerge/fuzz && cargo +nightly fuzz build && popd" &&     mv automerge/fuzz/target/x86_64-unknown-linux-gnu/release/decode_state /decode_state &&     mv automerge/fuzz/target/x86_64-unknown-linux-gnu/release/load_incremental /load_incremental &&     echo done

RUN echo building non-instrumented harnesses &&     export RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" &&     bash -c "pushd automerge/fuzz && cargo +nightly build --release && popd" &&     mv automerge/fuzz/target/release/decode_state /decode_state_no_inst &&     mv automerge/fuzz/target/release/load_incremental /load_incremental_no_inst &&     echo done

# Package Stage
FROM ubuntu:22.04

COPY --from=builder /decode_state /decode_state_no_inst /
COPY --from=builder /load_incremental /load_incremental_no_inst /
