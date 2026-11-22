# MOUSE driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-mouse-sys` and a `no_std` safe API in
`rust/insper-riscv-mouse`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_mouse_new(instance)` or `Mouse::instance(instance)`;
`Mouse::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/MOUSE`.
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
projects in `vendor/MOUSE/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_mouse_read_status_clear`: Read mouse status once; clears NEW, OVERFLOW and ERROR flags.
- `rv32_mouse_take_dx`: Consume the accumulated signed X displacement.
- `rv32_mouse_take_dy`: Consume the accumulated signed Y displacement.
- `rv32_mouse_buttons`: Read left/right/middle button bits without clearing motion.
- `rv32_mouse_enable_interrupt`: Enable new-packet interrupts; reading status clears the cause.
- `rv32_mouse_reinitialize`: Restart initialization while preserving the interrupt enable.
