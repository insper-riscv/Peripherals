# ETH driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-eth-sys` and a `no_std` safe API in
`rust/insper-riscv-eth`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_eth_new(instance)` or `Ethernet::instance(instance)`;
`Ethernet::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/ETH`.
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
projects in `vendor/ETH/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_eth_enable_receive`: Control this MAC option while serializing configuration changes.
- `rv32_eth_promiscuous`: Control this MAC option while serializing configuration changes.
- `rv32_eth_broadcast`: Control this MAC option while serializing configuration changes.
- `rv32_eth_multicast`: Control this MAC option while serializing configuration changes.
- `rv32_eth_accept_errors`: Control this MAC option while serializing configuration changes.
- `rv32_eth_hold_phy_reset`: Control this MAC option while serializing configuration changes.
- `rv32_eth_reset`: Request a MAC reset; hardware clears registers and queues.
- `rv32_eth_tx_busy`: Read the current hardware state without clearing events.
- `rv32_eth_rx_ready`: Read the current hardware state without clearing events.
- `rv32_eth_mdio_busy`: Read the current hardware state without clearing events.
- `rv32_eth_phy_interrupt`: Read the current hardware state without clearing events.
- `rv32_eth_mdio_no_ack`: Read the current hardware state without clearing events.
- `rv32_eth_clear_events`: Acknowledge RX/TX/error/MDIO events; PHY level is not W1C.
- `rv32_eth_receive_interrupt`: Enable this Ethernet interrupt source.
- `rv32_eth_transmit_interrupt`: Enable this Ethernet interrupt source.
- `rv32_eth_error_interrupt`: Enable this Ethernet interrupt source.
- `rv32_eth_mdio_interrupt`: Enable this Ethernet interrupt source.
- `rv32_eth_phy_irq_enable`: Enable this Ethernet interrupt source.
- `rv32_eth_transmitted_frames`: Read this hardware frame counter without clearing it.
- `rv32_eth_received_frames`: Read this hardware frame counter without clearing it.
- `rv32_eth_crc_errors`: Read this hardware frame counter without clearing it.
- `rv32_eth_phy_errors`: Read this hardware frame counter without clearing it.
- `rv32_eth_dropped_frames`: Read this hardware frame counter without clearing it.
- `rv32_eth_filtered_frames`: Read this hardware frame counter without clearing it.
- `rv32_eth_receive_length`: Length of the ready frame, excluding FCS.
- `rv32_eth_mdio_data`: Result of the last completed MDIO read.
- `rv32_eth_set_mac`: Set the six octets in wire order, without host-endian casts.
- `rv32_eth_send`: Queue one frame; hardware supplies padding/FCS and does not wait for completion.
- `rv32_eth_receive`: Copy and release a ready frame; a short destination leaves it pending.
- `rv32_eth_mdio_start`: Start one Clause-22 MDIO transaction without polling indefinitely.

This is a MAC/MDIO driver, not a TCP/IP stack or board-specific PHY initialization.
