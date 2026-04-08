# Build Stage
FROM rustlang/rust:nightly AS builder

RUN apt update && apt upgrade -y && \
    apt install -y clang-19 llvm-19-tools && \
    ln -s /usr/bin/llvm-config-19 /usr/bin/llvm-config

RUN rustup component add rust-src
RUN cargo install -f cargo-fuzz
RUN cargo install -f cargo-afl


## Add source code to the build stage.
ADD . /src
WORKDIR /src

RUN echo building instrumented harnesses && \
    bash -c "pushd automerge/fuzz && cargo +nightly -Z sparse-registry fuzz build && popd" && \
    mv automerge/fuzz/target/x86_64-unknown-linux-gnu/release/decode_state /decode_state && \
    mv automerge/fuzz/target/x86_64-unknown-linux-gnu/release/load_incremental /load_incremental && \
    echo done

RUN echo building non-instrumented harnesses && \
    export RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" && \
    bash -c "pushd automerge/fuzz && cargo +nightly -Z sparse-registry build --release && popd" && \
    mv automerge/fuzz/target/release/decode_state /decode_state_no_inst && \
    mv automerge/fuzz/target/release/load_incremental /load_incremental_no_inst && \
    echo done

# Package Stage
FROM rustlang/rust:nightly

COPY --from=builder /decode_state /decode_state_no_inst /
COPY --from=builder /load_incremental /load_incremental_no_inst /
