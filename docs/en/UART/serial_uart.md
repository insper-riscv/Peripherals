# Serial UART

## 1. What it is

A memory-mapped serial UART connects the core bus to physical asynchronous lines. Two synchronous queues separate processor access speed from serial frame duration. The transmit queue stores bytes written by the core, and the receive queue stores bytes delivered by the physical layer. The frame format (parity and stop bits) and the hardware flow control are optional and off at reset, so the UART starts as an 8N1 UART with only RX and TX.

| Item | Initial value |
| :--- | :--- |
| Baud rate | 115200 |
| Clock | 50 MHz |
| Format | 8 data bits, no parity, and 1 stop bit |
| Flow control | Absent (generic `has_flow_control` false) |
| TX depth | 16 bytes |
| RX depth | 16 bytes |
| Memory-mapped access | 1 cycle without bus wait |

The TX and RX depths are independent parameters from 1 through 255. The baud generator parameters support another clock without changing the queue logic. The data bus is at least 32 bits wide.

## 2. Byte flow

A write to `TX_DATA` adds the byte to the tail of TX. When the physical transmitter is free, it automatically removes the oldest byte and starts a frame. The processor can keep writing while space remains.

Every received frame adds one byte to the tail of RX. A read of `RX_DATA` returns the oldest byte and removes it at the edge that ends the access. An arrival simultaneous with that read reuses the released position without reporting an error.

## 3. Registers

| Word | Name | Read | Write |
| ---: | :--- | :--- | :--- |
| 0 | `TX_DATA` | Zero | Queues bits 7:0 in TX |
| 1 | `RX_DATA` | Bits 7:0 of the oldest byte, removed at the end of the access | Ignored |
| 2 | `STATUS` | State, errors, and levels described below | A one in an error bit clears it |
| 3 | `CONTROL` | Enables, frame format, and flow control, described below | Stores every field |

| `STATUS` bits | Name | Meaning |
| :--- | :--- | :--- |
| 0 | `RX_VALID` | The receive queue holds at least one byte |
| 1 | `TX_READY` | The transmit queue has at least one free position |
| 2 | `RX_OVERRUN` | A received byte was dropped because RX was full |
| 3 | `TX_DROPPED` | A write was dropped because TX was full |
| 4 | `RX_FULL` | The receive queue is full |
| 5 | `TX_EMPTY` | No byte waits in the transmit queue |
| 6 | `TX_IDLE` | TX is empty and the physical transmitter finished the last frame |
| 7 | `FRAME_ERROR` | The stop bit of a received frame was zero |
| 15:8 | `RX_LEVEL` | Number of bytes in the receive queue |
| 23:16 | `TX_LEVEL` | Number of bytes in the transmit queue |
| 24 | `PARITY_ERROR` | The parity bit of a received frame does not match the byte |
| 25 | `CTS_ACTIVE` | Read only. The `i_uart_cts` line is active (only with `has_flow_control`, otherwise zero) |
| 26 | `RTS_ACTIVE` | Read only. The `o_uart_rts` line is active (only with `has_flow_control`, otherwise zero) |

| `CONTROL` bits | Name | Meaning |
| :--- | :--- | :--- |
| 0 | `RX_IRQ_ENABLE` | Interrupt on a received byte |
| 1 | `TX_EMPTY_IRQ_ENABLE` | Interrupt on an empty transmit queue |
| 2 | `ERROR_IRQ_ENABLE` | Interrupt on `RX_OVERRUN` or `TX_DROPPED` |
| 3 | `PARITY_ENABLE` | Adds the parity bit after the data bits, in transmission and in reception |
| 4 | `PARITY_ODD` | Odd parity when one, even when zero (applies with `PARITY_ENABLE`) |
| 5 | `STOP_BITS_2` | Two stop bits in transmission |
| 6 | `LINE_ERROR_IRQ_ENABLE` | Interrupt on `FRAME_ERROR` or `PARITY_ERROR` |
| 7 | `FLOW_ENABLE` | Turns the flow control on (only with `has_flow_control`, otherwise zero) |
| 15:8 | `RTS_THRESHOLD` | RTS threshold in bytes (only with `has_flow_control`, otherwise zero) |

`TX_READY` allows the software to keep producing bytes without waiting for the current frame to end. Software that must guarantee the last bit reached the pin waits for `TX_IDLE`.

## 4. Frame format

The default frame has one start bit, eight data bits from least to most significant, and one stop bit. The `CONTROL` fields change the format in both directions.

| `PARITY_ENABLE` | `STOP_BITS_2` | Frame bits | Format |
| :--- | :--- | ---: | :--- |
| 0 | 0 | 10 | 8N1 |
| 1 | 0 | 11 | 8E1 or 8O1, by `PARITY_ODD` |
| 0 | 1 | 11 | 8N2 |
| 1 | 1 | 12 | 8E2 or 8O2 |

Even parity makes the number of ones among the data and the parity bit even, and odd parity makes it odd. The receiver checks the parity and the first stop bit, and samples in the middle of each bit. A second stop bit exists only in transmission, and the receiver treats it as the idle line. The format should change only with the line idle and with TX and RX empty, because a frame in progress uses the format that held when it started.

A byte received with an error enters the queue like any other. The error stays in the `FRAME_ERROR` and `PARITY_ERROR` flags, which the software reads in `STATUS`, and it is not born with the byte, because the receiver knows the parity bit and the stop bit only after delivering the byte. A line held at zero for longer than one frame (a break condition) produces frames of zeros with a repeating `FRAME_ERROR`.

## 5. Errors and interrupt

`RX_OVERRUN`, `TX_DROPPED`, `FRAME_ERROR`, and `PARITY_ERROR` are persistent. A write of one to its own bit in `STATUS` clears it, and a write of zero preserves it. A new error in the same cycle as a clear has priority and keeps the bit active.

When RX is full, the new byte is dropped and all older bytes remain in order. When TX is full, the new write is dropped without changing the bytes that already wait.

The `o_irq` output is level-based and equals the sum of four causes, each with its own enable, all cleared at reset.

| Cause | Condition | Stops holding when |
| :--- | :--- | :--- |
| Receive (`RX_IRQ_ENABLE`) | RX is not empty | The software removes the last byte |
| Transmitter empty (`TX_EMPTY_IRQ_ENABLE`) | TX is empty | The software writes `TX_DATA` |
| Queue error (`ERROR_IRQ_ENABLE`) | `RX_OVERRUN` or `TX_DROPPED` active | The software clears the bit in `STATUS` |
| Line error (`LINE_ERROR_IRQ_ENABLE`) | `FRAME_ERROR` or `PARITY_ERROR` active | The software clears the bit in `STATUS` |

With TX empty, the transmitter-empty cause holds as soon as it is enabled, so the software enables it only when it has bytes to send and disables it when done.

## 6. Hardware flow control

With the `has_flow_control` generic true, the UART has two more lines, `i_uart_cts` (input) and `o_uart_rts` (output). With the generic false, the input is ignored, the output stays active, and the `FLOW_ENABLE`, `RTS_THRESHOLD`, `CTS_ACTIVE`, and `RTS_ACTIVE` fields do not exist (they read zero and writes are ignored). In both cases the control acts only after the software sets `FLOW_ENABLE`, which is zero at reset.

Both lines are active low, the convention of the `RTS#` and `CTS#` signals on the TTL side of an RS-232 transceiver. The DE2-115 manual (section 4.12) names the pins `UART_CTS` and `UART_RTS` but does not state the polarity, which is therefore not confirmed in the board manual. An adapter with the opposite polarity needs an inversion in the top level.

| Rule | Effect |
| :--- | :--- |
| `i_uart_cts` inactive (high) | The transmitter does not start a new frame. The frame in progress ends and the bytes wait in the TX queue |
| `i_uart_cts` active (low) | The queued bytes leave in order |
| RX with `RTS_THRESHOLD` bytes or more | `o_uart_rts` becomes inactive (high) |
| RX with fewer than `RTS_THRESHOLD` bytes | `o_uart_rts` becomes active (low) |

`o_uart_rts` comes from a register and follows the receive queue level with one cycle of delay. `i_uart_cts` passes through two registers before it takes effect, because it comes from outside the clock domain. The threshold is `RTS_THRESHOLD` in bytes and, at reset, half of the receive queue (at least 1). A zero threshold keeps `o_uart_rts` always inactive.

The other side can finish a frame that had already started when `o_uart_rts` became inactive, and reception continues to the end of that frame. The threshold must therefore leave at least one byte of slack in the queue, which holds for any threshold below the depth of the receive queue.

On the DE2-115 the lines connect the FPGA to the ZT3232 transceiver and the DB9 connector, on the pins of table 4-18 of the manual.

| Signal | FPGA pin | Direction |
| :--- | :--- | :--- |
| `UART_RXD` | `PIN_G12` | Input |
| `UART_TXD` | `PIN_G9` | Output |
| `UART_CTS` | `PIN_G14` | Input |
| `UART_RTS` | `PIN_J13` | Output |

The cable between the DB9 connector and the computer can be straight or crossed, and the manual does not say which connector pin each signal uses. The test on the board with a real terminal confirms the wiring, and the terminal must have hardware flow control (RTS and CTS) on.

## 7. UART on the expansion headers

The peripheral UART has only RX and TX (and, with the generic, RTS and CTS). On boards without an RS-232 transceiver the structural top level connects pins of an expansion header to those signals, without changing the entity. The pins are 3.3 V LVTTL, and an RS-232 connector is never wired to them. Whoever uses the UART off the board connects a 3.3 V USB-serial adapter (or a level transceiver), crossing TX and RX, and connects the ground as well.

| Board | Header | `o_uart_tx` | `i_uart_rx` | `o_uart_rts` | `i_uart_cts` | Manual source |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| DE0-CV | `GPIO_0` | `GPIO_0[0]` (N16) | `GPIO_0[1]` (B16) | `GPIO_0[7]` (K22) | `GPIO_0[8]` (M20) | Table 3-7 |
| DE0-Nano | `GPIO_0` | `GPIO_0[0]` (D3) | `GPIO_0[1]` (C3) | `GPIO_0[2]` (A2) | `GPIO_0[3]` (A3) | Section 3.5, table 3-6 |
| DE10-Lite | Arduino | `ARDUINO_IO[1]` (AB6) | `ARDUINO_IO[0]` (AB5) | `ARDUINO_IO[2]` (AB7) | `ARDUINO_IO[3]` (AB8) | Section 3.6, table 3-8 |
| DE0-Nano-SoC | Arduino | `ARDUINO_IO[1]` (AF13) | `ARDUINO_IO[0]` (AG13) | `ARDUINO_IO[2]` (AG10) | `ARDUINO_IO[3]` (AG9) | Section 3.6.3, table 3-11 |
| DE10-Nano | Arduino | `ARDUINO_IO[1]` (AF13) | `ARDUINO_IO[0]` (AG13) | `ARDUINO_IO[2]` (AG10) | `ARDUINO_IO[3]` (AG9) | Section 3.6.3, table 3-11 |

On the Arduino headers of the last four boards the manual labels `Arduino_IO0` as `RXD` and `Arduino_IO1` as `TXD`, and leaves `Arduino_IO2` and `Arduino_IO3` without a function, which is the reason for the choice in the table. On the two boards with a `GPIO_0` header, the choice of RX and TX on the first two pins and of RTS and CTS on free pins belongs to the project, not to the manual. On the DE0-CV the pins `GPIO_0[2]`, `GPIO_0[3]`, `GPIO_0[4]`, and `GPIO_0[6]` are reserved for an external FLASH chip in the board catalog and do not serve the UART. The DE2-115 has the UART on the pins of section 6 and does not need this map.

The top level declares the four signals as ports and connects them to the UART by named association, with no logic of its own.

```vhdl
u_uart : entity work.uart
    generic map (
        has_flow_control => true
    )
    port map (
        i_clk      => i_clk,
        i_rst      => i_rst,
        i_data_in  => bus_wdata,
        i_address  => bus_address,
        i_write    => bus_write,
        i_read     => bus_read,
        o_data_out => bus_rdata,
        o_irq      => uart_irq,
        i_uart_rx  => uart_rxd,
        o_uart_tx  => uart_txd,
        i_uart_cts => uart_cts,
        o_uart_rts => uart_rts
    );
```

The signals `uart_rxd`, `uart_txd`, `uart_cts`, and `uart_rts` are the top-level ports tied to the pins of the table, and the same pins do not enter any GPIO group of the SoC. Without flow control the top level omits the generic and the two ports.

The platform console uses the UART through the `pinos` backend, which forwards `has_flow_control`, `i_cts`, and `o_rts` (see `console.md`).

## 8. Integration interface

| Item | Value |
| :--- | :--- |
| Entity | `uart` |
| Generics | `data_width` (minimum 32), `baud_freq`, `baud_limit`, `rx_fifo_depth`, `tx_fifo_depth`, `has_flow_control` (false by default) |
| Bus ports | `i_clk`, `i_rst`, `i_data_in`, `i_address` (2 bits), `i_write`, `i_read`, `o_data_out`, `o_irq` |
| Line ports | `i_uart_rx`, `o_uart_tx`, `i_uart_cts` (default value `'0'`, active), `o_uart_rts` |
| Registers | `TX_DATA` 0, `RX_DATA` 1, `STATUS` 2, `CONTROL` 3 |

## 9. C example

The file `src/UART/serial/example/uart_flow.c` sets 8E1 with flow control and an 8-byte threshold, sends a line, and echoes the received bytes while counting frame and parity errors. The UART base address comes from the platform and enters the build with `-DUART_BASE`, and the file follows the repository C23.

## 10. Verification

The entity tests exercise reset, ordering, filling, draining, pointer wraparound, simultaneous insert and remove, levels, interrupt, persistent errors, 8N1 frames, and the default 115200 baud timing at 50 MHz.

| Test | File | What it shows |
| :--- | :--- | :--- |
| `UARTFormat` | `tests/python/unittests/UART/uart_format.py` | Transmit frames with even and odd parity and one or two stop bits, loopback in every format, persistent `PARITY_ERROR` and `FRAME_ERROR` that keep the byte, and the line error interrupt with its own enable |
| `UARTFlow` | `tests/python/unittests/UART/uart_flow.py` | Flow registers, no frame with CTS inactive, a frame in progress that finishes, RTS that follows the level and the register threshold, a modeled terminal that obeys RTS without losing a byte, the same terminal without flow control that loses bytes, and the UART in loopback with RTS tied to its own CTS |

The formal proof uses `formal/uart_props.sv` for the frame format (start, data, parity, and stop in transmission, and the line errors in reception) and `formal/uart_flow_props.sv` for the flow control. No byte leaves the transmit queue for the transmitter with the flow on and CTS inactive, and `o_uart_rts` is the register of "flow on and RX level at or above the threshold". With the flow off, CTS is ignored and RTS stays active. The proofs, the mutants, and the engines are in `docs/en/formal/formal.md`.
