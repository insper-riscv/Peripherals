# SPI driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-spi-sys` and a `no_std` safe API in
`rust/insper-riscv-spi`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_spi_new(instance)` or `Spi::instance(instance)`;
`Spi::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/SPI`.
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
projects in `vendor/SPI/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_spi_busy`: Whether queued or active transfers are still pending.
- `rv32_spi_tx_ready`: Whether the transmit queue accepts another word.
- `rv32_spi_rx_ready`: Whether the receive queue contains data.
- `rv32_spi_receive_level`: Receive queue occupancy.
- `rv32_spi_transmit_level`: Transmit queue occupancy.
- `rv32_spi_try_read`: Pop one received word, or return no data.
- `rv32_spi_try_write`: Queue one word without waiting.
- `rv32_spi_try_listen`: Clock a word while releasing MOSI.
- `rv32_spi_clear_events`: Clear only DONE, RX_OVERRUN and TX_DROPPED (W1C).
- `rv32_spi_set_divider`: Set the hardware half-clock divider.
- `rv32_spi_receive_interrupt`: Enable this interrupt source; CPU interrupt routing is separate.
- `rv32_spi_empty_interrupt`: Enable this interrupt source; CPU interrupt routing is separate.
- `rv32_spi_done_interrupt`: Enable this interrupt source; CPU interrupt routing is separate.
- `rv32_spi_error_interrupt`: Enable this interrupt source; CPU interrupt routing is separate.
- `rv32_spi_configure`: Configure mode and width while idle; preserve chip select and IRQ masks.
- `rv32_spi_select`: Select a numbered chip-select line while idle.
