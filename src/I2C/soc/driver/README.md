# I2C driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-i2c-sys` and a `no_std` safe API in
`rust/insper-riscv-i2c`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_i2c_new(instance)` or `I2c::instance(instance)`;
`I2c::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/I2C`.
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
projects in `vendor/I2C/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_i2c_enable`: Enable the I2C controller.
- `rv32_i2c_done_interrupt`: Enable command completion interrupts.
- `rv32_i2c_error_interrupt`: Enable NACK/arbitration/rejection interrupts.
- `rv32_i2c_abort`: Abort and release the bus; preserve interrupt enables.
- `rv32_i2c_busy`: Whether a command is executing.
- `rv32_i2c_bus_active`: Whether a transaction remains open.
- `rv32_i2c_done`: Whether the last command completed.
- `rv32_i2c_nack`: Whether the slave failed to acknowledge.
- `rv32_i2c_arbitration_lost`: Whether arbitration was lost.
- `rv32_i2c_rejected`: Whether hardware rejected a command.
- `rv32_i2c_clear_events`: Clear only sticky completion/error flags (W1C).
- `rv32_i2c_set_divider`: Configure a validated I2C clock divider.
- `rv32_i2c_command`: Submit one valid bus action without waiting.
- `rv32_i2c_start_write`: Queue this I2C bus action; disabled/busy/closed-bus state can block it.
- `rv32_i2c_write_byte`: Queue this I2C bus action; disabled/busy/closed-bus state can block it.
- `rv32_i2c_write_stop`: Queue this I2C bus action; disabled/busy/closed-bus state can block it.
- `rv32_i2c_read_ack`: Queue this I2C bus action; disabled/busy/closed-bus state can block it.
- `rv32_i2c_read_stop`: Queue this I2C bus action; disabled/busy/closed-bus state can block it.
- `rv32_i2c_stop`: Queue this I2C bus action; disabled/busy/closed-bus state can block it.
- `rv32_i2c_received_byte`: Read the byte from the last completed read command.
