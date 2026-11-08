# 2. Console (contract K9)

## 1. Scope

The console is the text channel between the program and the host. This contract defines the two backends and when each one applies. The program always sees a UART behind the interconnect (contract K6), and the backend only changes what is on the other side. The entity that implements the contract is the [console](../UART/console.md), which picks the backend through a generic.

## 2. Backends

| Backend | Contract | When |
| :--- | :--- | :--- |
| `jtag` (default) | UART peripheral with a Virtual JTAG node ([jtag_uart](../UART/jtag_uart.md)) | Every board with a JTAG chain reachable by Quartus |
| `pinos` (pins) | UART peripheral with `o_tx` and `i_rx` ([serial_uart](../UART/serial_uart.md)) | Boards with a UART or with a GPIO adapter |

## 3. Choice

`jtag` is the default because not every board has a USB-serial bridge wired to the FPGA, while JTAG exists on all of them. `pinos` is optional: it asks for the `o_tx` and `i_rx` pins on the board, and a board that does not offer them does not accept it. The Virtual JTAG node is a vendor primitive and lives in the vendor wrapper, never in the peripheral.

## 4. JTAG chain with an embedded processor

When the FPGA shares the chain with a processor (HPS), the Virtual JTAG node stays reachable through the chain. The USB UART of those boards belongs to the processor and does not reach the FPGA, so their console is `jtag`.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
