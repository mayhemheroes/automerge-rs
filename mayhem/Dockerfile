# Build Stage
FROM ubuntu:22.04 AS builder

RUN apt-get update && apt-get install -y curl build-essential
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly
ENV PATH=/root/.cargo/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

RUN cargo install cargo-fuzz

ADD . /src
WORKDIR /src/rust/automerge

RUN echo building instrumented harnesses && \
    cargo +nightly fuzz build && \
    mv fuzz/target/x86_64-unknown-linux-gnu/release/load /load && \
    echo done

RUN echo building non-instrumented harnesses && \
    export RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" && \
    cargo +nightly build --release --manifest-path fuzz/Cargo.toml && \
    mv fuzz/target/release/load /load_no_inst && \
    echo done

# Package Stage
FROM ubuntu:22.04

COPY --from=builder /load /load_no_inst /
