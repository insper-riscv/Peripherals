#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Native API/doctests and both supported bare-metal ABIs, serial by workspace.
# Requires Rust >=1.85, libclang, clang, clippy and both rustup RV32 targets.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"

while IFS= read -r -d '' manifest; do
    cargo fmt --all --manifest-path "${manifest}" -- --check
    cargo test --workspace --manifest-path "${manifest}"
    cargo clippy --workspace --all-targets --manifest-path "${manifest}" -- -D warnings
    for target in riscv32i-unknown-none-elf riscv32im-unknown-none-elf; do
        cargo build --workspace --release --target "${target}" --manifest-path "${manifest}"
    done
done < <(find src -path '*/driver/rust/Cargo.toml' -not -path 'src/common/*' -print0 | sort -z)
