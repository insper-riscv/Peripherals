# WIFI driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-wifi-sys` and a `no_std` safe API in
`rust/insper-riscv-wifi`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_wifi_new(instance)` or `Wifi::instance(instance)`;
`Wifi::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/WIFI`.
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
projects in `vendor/WIFI/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_wifi_run`: Release or hold module reset; firmware startup is asynchronous.
- `rv32_wifi_bootloader_mode`: Drive GPIO0 low for the external firmware bootloader.
- `rv32_wifi_rise_interrupt`: Enable rising ACK edge interrupts.
- `rv32_wifi_fall_interrupt`: Enable falling ACK edge interrupts.
- `rv32_wifi_acknowledge`: Read the synchronized module ACK line.
- `rv32_wifi_resetting`: Whether a timed module reset pulse is active.
- `rv32_wifi_clear_events`: Clear ACK rising/falling edge flags with W1C writes.
- `rv32_wifi_reset_pulse`: Request the hardware-timed reset pulse; no software delay is invented.
- `rv32_wifi_spi_busy`: Whether the SPI transport still has pending work.
- `rv32_wifi_spi_try_read`: Pop one SPI transport byte.
- `rv32_wifi_spi_try_write`: Queue one SPI transport byte.
- `rv32_wifi_spi_set_divider`: Set the SPI half-clock divider.
- `rv32_wifi_spi_select`: Change chip select only while the SPI transport is idle.
- `rv32_wifi_uart_try_read`: Pop one UART transport byte.
- `rv32_wifi_uart_try_write`: Queue one UART transport byte.
- `rv32_wifi_spi_clear_events`: Clear the SPI transport sticky events (W1C).
- `rv32_wifi_uart_clear_errors`: Clear UART receive-overflow and transmit-drop flags (W1C).

This exposes the NINA transport/control interface, not an AT-command, WiFiNINA or TCP/IP protocol stack.
