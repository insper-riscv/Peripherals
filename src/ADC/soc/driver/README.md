# ADC driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-adc-sys` and a `no_std` safe API in
`rust/insper-riscv-adc`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_adc_new(instance)` or `Adc::instance(instance)`;
`Adc::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/ADC`.
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
projects in `vendor/ADC/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_adc_channel_count`: Number of channels of this converter backend.
- `rv32_adc_busy`: Whether a conversion sweep is active.
- `rv32_adc_done`: Whether a sweep completed since acknowledgement.
- `rv32_adc_continuous`: Enable or stop continuous sweeps; an active conversion completes normally.
- `rv32_adc_enable_interrupt`: Enable the backend-specific sweep-done interrupt.
- `rv32_adc_start`: Start one sweep without waiting; busy hardware can block the request.
- `rv32_adc_clear_events`: Acknowledge only backend-defined W1C completion/error flags.
- `rv32_adc_read_channel`: Read a numbered channel; MAX10 VALID/OVERRUN are consumed by this read.
- `rv32_adc_channel`: Validate a logical channel once and borrow its originating converter.
- `rv32_adc_set_mask`: Select MAX10 scan channels while idle; external converters always scan all eight.
- `rv32_adc_set_period`: Set the MAX10 continuous-scan period while idle.
- `rv32_adc_set_serial_divider`: Set the external ADC serial divider while idle; unavailable on MAX10.
