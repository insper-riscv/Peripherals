# IR driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-ir-sys` and a `no_std` safe API in
`rust/insper-riscv-ir`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_ir_new(instance)` or `Ir::instance(instance)`;
`Ir::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/IR`.
For Rust it adds only the safe crate as a direct Cargo dependency; the sys
crate builds and links the same C implementation. Do not edit generated files
in place: regeneration refuses to overwrite hand edits.

C operations validate their handle/arguments. Rust validates handles and
bounded values at construction, then uses private fields and borrowing handles
for pins, channels and buffer words. Register accesses with no runtime failure
are infallible; FIFO readiness, busy devices and bounded polling remain
fallible. Serialize configuration with other handles and interrupt handlers;
these wrappers do not provide a system-wide lock or an interrupt dispatcher.

The `c/examples/main.c.in` and `main.rs.in` templates become independent
projects in `vendor/IR/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_ir_enable`: Enable reception without flushing pending frames.
- `rv32_ir_frame_interrupt`: Enable frame-available interrupts.
- `rv32_ir_error_interrupt`: Enable malformed-frame and overflow interrupts.
- `rv32_ir_extended_addresses`: Accept extended 16-bit NEC addresses.
- `rv32_ir_raw_interrupt`: Enable raw timing measurement interrupts.
- `rv32_ir_flush`: Discard queued frames without altering enables.
- `rv32_ir_ready`: Whether a complete NEC frame is queued.
- `rv32_ir_clear_events`: Clear frame error, overflow and raw-new flags (W1C).
- `rv32_ir_try_read`: Pop one packed NEC frame; None means the FIFO is empty.
- `rv32_ir_raw_mark_cycles`: Duration of the most recent infrared mark.
- `rv32_ir_raw_space_cycles`: Duration of the most recent infrared space.
