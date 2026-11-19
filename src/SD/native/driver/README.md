# SD driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-sd-sys` and a `no_std` safe API in
`rust/insper-riscv-sd`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_sd_new(instance)` or `Sd::instance(instance)`;
`Sd::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/SD`.
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
projects in `vendor/SD/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_sd_command_busy`: Read the current command/data engine state.
- `rv32_sd_data_busy`: Read the current command/data engine state.
- `rv32_sd_command_done`: Read the current command/data engine state.
- `rv32_sd_data_done`: Read the current command/data engine state.
- `rv32_sd_card_busy`: Read the current command/data engine state.
- `rv32_sd_errors`: Read sticky command and data error flags.
- `rv32_sd_clear_events`: Clear only CMD_DONE and DATA_DONE flags (W1C).
- `rv32_sd_clear_errors`: Clear only defined command/data error flags (W1C).
- `rv32_sd_clock_enable`: Configure this SD controller option; card negotiation is separate.
- `rv32_sd_wide_bus`: Configure this SD controller option; card negotiation is separate.
- `rv32_sd_command_interrupt`: Configure this SD controller option; card negotiation is separate.
- `rv32_sd_data_interrupt`: Configure this SD controller option; card negotiation is separate.
- `rv32_sd_error_interrupt`: Configure this SD controller option; card negotiation is separate.
- `rv32_sd_abort`: Abort the command/data engine and release the lines.
- `rv32_sd_set_divider`: Set the SD clock divider for the current negotiation stage.
- `rv32_sd_set_timeout`: Set a validated hardware wait limit in SD clocks.
- `rv32_sd_command`: Submit one typed command; no filesystem/card-protocol assumptions are hidden.
- `rv32_sd_response0`: Read this word of the last response.
- `rv32_sd_response1`: Read this word of the last response.
- `rv32_sd_response2`: Read this word of the last response.
- `rv32_sd_response3`: Read this word of the last response.
- `rv32_sd_read_buffer`: Access a bounded range of the 128-word block buffer while the engine is idle.
- `rv32_sd_write_buffer`: Access a bounded range of the 128-word block buffer while the engine is idle.

This is a controller driver, not an SD-card initialization sequence or filesystem.
