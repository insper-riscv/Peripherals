# KEYBOARD driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-keyboard-sys` and a `no_std` safe API in
`rust/insper-riscv-keyboard`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_keyboard_new(instance)` or `Keyboard::instance(instance)`;
`Keyboard::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/KEYBOARD`.
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
projects in `vendor/KEYBOARD/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_keyboard_try_read`: Pop one set-2 scan-code byte; None means no queued byte.
- `rv32_keyboard_try_command`: Send a keyboard command only when the transmitter is ready.
- `rv32_keyboard_queue_level`: Queued scan-code bytes.
- `rv32_keyboard_ready`: Whether a scan-code byte is available.
- `rv32_keyboard_receive_interrupt`: Enable scan-code receive interrupts.
- `rv32_keyboard_error_interrupt`: Enable framing and overflow interrupts.
- `rv32_keyboard_clear_errors`: Clear only receive overflow, receive error and dropped command.
