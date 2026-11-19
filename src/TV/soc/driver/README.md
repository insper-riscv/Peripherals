# TV driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-tv-sys` and a `no_std` safe API in
`rust/insper-riscv-tv`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_tv_new(instance)` or `Tv::instance(instance)`;
`Tv::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/TV`.
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
projects in `vendor/TV/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_tv_enable`: Release the external receiver reset and enable its clock domain.
- `rv32_tv_frame_interrupt`: Enable frame-ready interrupts.
- `rv32_tv_error_interrupt`: Enable receiver-error interrupts.
- `rv32_tv_busy`: Whether a capture is in progress.
- `rv32_tv_ready`: Whether a completed frame is available.
- `rv32_tv_has_error`: Whether a capture error is pending.
- `rv32_tv_clear_events`: Acknowledge frame-ready and error flags with W1C writes.
- `rv32_tv_frame_count`: Number of completed frames.
- `rv32_tv_width`: Frame width (TV pixels or MIPI bytes per line).
- `rv32_tv_height`: Frame height in lines.
- `rv32_tv_start`: Request one capture; disabled/busy receiver state can block it.
- `rv32_tv_word_count`: Read the immutable frame-memory capacity in 32-bit words.
- `rv32_tv_read_words`: Read a bounded frame range while capture is idle; no invented settle delay.
- `rv32_tv_set_decimation`: Set nonzero X/Y decimation factors while idle.

External codec/sensor/transmitter setup remains board/device specific. No undocumented initialization sequence is assumed.
