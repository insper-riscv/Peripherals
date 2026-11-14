# PLIC Rust driver

`insper-riscv-plic` provides the no_std, address-free `Plic` API.
`insper-riscv-plic-sys` builds and binds the sibling C implementation.
Each public operation has a compiling `no_run` Rust documentation example.

Enable `generate_drivers = true` in rv32.toml. SDK setup copies both crates into
vendor/PLIC/rust and adds the path dependency automatically when this peripheral
is enabled in the selected CPU profile/platform. Hardware widths, queue backend,
priorities and addresses are generated, never application constructor arguments.
Without configuration constructors safely return Error::Unavailable.

Configuration is foreground-only: these handles are not Send/Sync; serialize
access with interrupt handlers. Polling budgets are counts, not elapsed time.
Flash commands can modify stored data; documentation examples are compile-only.

Run cargo test --workspace, cargo test --doc --workspace, and build for
riscv32i-unknown-none-elf / riscv32im-unknown-none-elf with -j 2.
