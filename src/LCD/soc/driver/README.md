# LCD driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-lcd-sys` and a `no_std` safe API in
`rust/insper-riscv-lcd`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_lcd_new(instance)` or `Lcd::instance(instance)`;
`Lcd::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/LCD`.
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
projects in `vendor/LCD/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_lcd_busy`: Whether initialization or a queued LCD operation is active.
- `rv32_lcd_initializing`: Whether the hardware initialization is active.
- `rv32_lcd_queue_level`: Queued commands and data bytes.
- `rv32_lcd_empty_interrupt`: Enable queue-empty interrupts.
- `rv32_lcd_busy_polling`: Use the LCD busy line when this backend provides it.
- `rv32_lcd_power`: Control the LCD power output.
- `rv32_lcd_backlight`: Control the LCD backlight output.
- `rv32_lcd_clear_errors`: Clear only dropped-write and timeout flags (W1C).
- `rv32_lcd_try_command`: Queue a controller command without waiting.
- `rv32_lcd_try_write`: Queue one character without waiting.
- `rv32_lcd_clear`: Queue clear-display; hardware supplies the required execution delay.
- `rv32_lcd_cursor`: Queue a position validated for the 16-by-2 display.
