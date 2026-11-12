# PS/2 keyboard (`ps2_keyboard`)

## 1. What it is

The memory-mapped PS/2 keyboard connects a keyboard to the core bus. It instantiates `ps2_host` (see [ps2_host.md](ps2_host.md)), stores the scancode bytes in a synchronous queue, and lets software send commands to the keyboard. Each instance is independent, so a keyboard and a mouse coexist on a Y cable, each on its own channel.

| Item | Value |
| :--- | :--- |
| Scancode set | Set 2 (make, break with the `0xF0` prefix, extended with the `0xE0` prefix) |
| DE0-CV channel | 0: `PS2_CLK` (D3) and `PS2_DAT` (G2) |
| Queue depth | 16 bytes (`rx_fifo_depth` parameter, 1 to 255) |
| Register block | 4 words (16 bytes), 2-bit `i_address` |
| Mapped access | 1 cycle, no bus wait |

## 2. Top-level ports and integration

| Port | Direction | Connection |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | System clock and active-high reset |
| `i_data_in`, `i_address` (2 bits), `i_write`, `i_read`, `o_data_out` | bus | 4-word slot on the interconnect |
| `o_irq` | output | Level interrupt source for the PLIC |
| `io_ps2_clk` | bidirectional | `PS2_CLK` pin (D3) |
| `io_ps2_dat` | bidirectional | `PS2_DAT` pin (G2) |

The `filter_cycles`, `inhibit_cycles` and `timeout_cycles` generics follow `ps2_host` and default to a 50 MHz clock. With another clock, the top level adjusts all three to keep a 160 ns filter, an inhibit of 100 us or more and a 20 ms limit.

## 3. Registers

| Word | Name | Read | Write |
| ---: | :--- | :--- | :--- |
| 0 | `DATA` | Bits 7:0 of the oldest byte, removed at the end of the access | Ignored |
| 1 | `STATUS` | State, errors and level described below | A one in an error bit clears it |
| 2 | `COMMAND` | Zero | Sends bits 7:0 to the keyboard |
| 3 | `CONTROL` | Bit 0 `RX_IRQ_ENABLE`, bit 1 `ERROR_IRQ_ENABLE` | Both bits enable the interrupt causes |

| `STATUS` bits | Name | Meaning |
| :--- | :--- | :--- |
| 0 | `RX_VALID` | At least one byte is in the queue |
| 1 | `TX_READY` | The transmitter accepts a command |
| 2 | `RX_OVERFLOW` | A received byte was dropped because the queue was full |
| 3 | `RX_ERROR` | Frame with invalid parity, start or stop, an interrupted frame, or a command without acknowledge |
| 4 | `RX_FULL` | The queue is full |
| 5 | `TX_DROPPED` | A write to `COMMAND` was dropped because the transmitter was busy |
| 15:8 | `RX_LEVEL` | Number of bytes in the queue |

Bits 2, 3 and 5 are sticky. A write of one to the bit itself clears it, and a write of zero preserves it. A new event in the same cycle as a clear takes priority.

## 4. Flow

Each correct keyboard frame enters the tail of the queue, and a read of `DATA` returns the oldest byte and removes it. A pressed key produces the make byte; on release, the `0xF0` prefix followed by the same byte; extended keys start with `0xE0`. With a full queue the new byte is dropped and the old ones stay in order.

A command (for example `0xFF` reset or `0xED` followed by the LED argument) is written to `COMMAND` when `TX_READY` is one. The keyboard answers with bytes (such as `0xFA`) that arrive through the queue. A write while the transmitter is busy is dropped and sets `TX_DROPPED`.

## 5. Interrupt

The `o_irq` output is level-sensitive and is the sum of two causes, each with its own enable, cleared at reset.

| Cause | Condition | Stops when |
| :--- | :--- | :--- |
| Receive (`RX_IRQ_ENABLE`) | The queue is not empty | Software removes the last byte |
| Error (`ERROR_IRQ_ENABLE`) | `RX_OVERFLOW` or `RX_ERROR` active | Software clears the bit in `STATUS` |

## 6. Verification

The entity tests cover the reset state, in-order delivery of make, break and extended codes, the overflow that preserves the old bytes, the parity error and its recovery, reset and LED commands with acknowledge, the drop with a busy transmitter, and the interrupt with and without enables.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
