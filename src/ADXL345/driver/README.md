# ADXL345 driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-adxl345-sys` and a `no_std` safe API in
`rust/insper-riscv-adxl345`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_adxl345_new(instance)` or `Adxl345::instance(instance)`;
`Adxl345::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/ADXL345`.
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
projects in `vendor/ADXL345/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_adxl345_x`: Read the signed raw axis sample; scaling depends on range/resolution.
- `rv32_adxl345_y`: Read the signed raw axis sample; scaling depends on range/resolution.
- `rv32_adxl345_z`: Read the signed raw axis sample; scaling depends on range/resolution.
- `rv32_adxl345_busy`: Whether a transaction is active or pending.
- `rv32_adxl345_sample_ready`: Whether a new sample arrived since acknowledgement.
- `rv32_adxl345_valid_sample`: Whether any sample has arrived since reset.
- `rv32_adxl345_configured`: Whether device configuration has completed.
- `rv32_adxl345_clear_events`: Clear SAMPLE and I2C NACK/arbitration flags without read-modify-write.
- `rv32_adxl345_enable`: Enable automatic device configuration and sampling.
- `rv32_adxl345_enable_interrupt`: Enable sample-available interrupts.
- `rv32_adxl345_full_resolution`: Select full-resolution operation on the next configuration.
- `rv32_adxl345_interrupt_triggered`: Use the external data-ready line instead of periodic sampling.
- `rv32_adxl345_device_id`: Read the identifier returned by the chip.
- `rv32_adxl345_set_divider`: Set the serial clock divider; I2C hardware clamps values below two.
- `rv32_adxl345_set_range`: Apply a validated accelerometer configuration value.
- `rv32_adxl345_set_rate`: Apply a validated accelerometer configuration value.
- `rv32_adxl345_set_period`: Apply a validated accelerometer configuration value.
