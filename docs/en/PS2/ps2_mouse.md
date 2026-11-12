# PS/2 Mouse

🌐 [Português](../../pt-br/PS2/ps2_mouse.md) · [English](../../en/PS2/ps2_mouse.md)

## 1. What it is

A bus peripheral that drives a three-button PS/2 mouse and hands the program the accumulated X and Y displacement, the button state and an optional interrupt. The `ps2_mouse` entity exchanges bytes with the `ps2_host` physical layer (one PS/2 channel) and keeps no state outside the instance, so several instances, each with its own `ps2_host`, coexist in one design, for example the keyboard on channel 0 and the mouse on channel 1.

The entity is made of four single-purpose blocks.

| Block | Function |
| :--- | :--- |
| `ps2_mouse_decoder` | Initialization sequence, assembly of the 3-byte packets and resynchronization |
| `ps2_axis_accumulator` | Saturating sum of the displacement of one axis, cleared on read (one instance per axis) |
| `ps2_mouse_operation_decoder` | Translation of the word address into the read selector and the clear pulses |
| `ps2_mouse` | Structural top with the status bits, the interrupt enable and the read multiplexer |

## 2. Registers

The address is a 3-bit word address and the block takes 8 words (32 bytes). Addresses 5 to 7 read zero and ignore writes.

| Word | Name | Read | Write |
| ---: | :--- | :--- | :--- |
| 0 | `STATUS` | Status bits of the table below; the read clears bits 0 to 2 | Ignored |
| 1 | `DX` | Accumulated X displacement, 16-bit two's complement, sign extended; the read clears the accumulator | Ignored |
| 2 | `DY` | Accumulated Y displacement (positive upwards), same format as `DX` | Ignored |
| 3 | `BUTTONS` | Bit 0 left, bit 1 right, bit 2 middle, as of the last packet | Ignored |
| 4 | `CONTROL` | Bit 0 enables the interrupt; bit 1 reads zero | Bit 0 sets the enable; writing 1 to bit 1 restarts the mouse |

Bits of `STATUS`.

| Bit | Name | Meaning |
| ---: | :--- | :--- |
| 0 | `NEW` | At least one packet arrived since the last read |
| 1 | `OVERFLOW` | A packet carried an axis overflow or an accumulator saturated since the last read |
| 2 | `ERROR` | A framing error, an unexpected answer, an out-of-sync byte or a silence happened since the last read |
| 3 | `STREAMING` | Initialization is over and the mouse sends packets (current level, not cleared by the read) |

A packet that arrives in the same cycle as the read of a register is not lost, because the value read is the previous one and the new one stays accumulated or flagged.

## 3. Protocol

### 3.1. Initialization

After reset the decoder sends the commands below and checks each answer.

| Step | Sends | Expects |
| ---: | :--- | :--- |
| 1 | `0xFF` (reset) | `0xFA` (ACK) |
| 2 | nothing | `0xAA` (self-test passed) |
| 3 | nothing | `0x00` (mouse identifier) |
| 4 | `0xF4` (enable streaming) | `0xFA` (ACK) |

An answer other than the expected one, a framing error or silence for `init_timeout_cycles` clock cycles set the `ERROR` bit and restart the sequence at step 1. The self-test of a mouse takes hundreds of milliseconds, and the default `init_timeout_cycles` covers one second at 100 MHz. Writing 1 to bit 1 of `CONTROL` also restarts the sequence.

### 3.2. Packets

In streaming mode each movement arrives in three bytes.

| Byte | Bit 7 | Bit 6 | Bit 5 | Bit 4 | Bit 3 | Bit 2 | Bit 1 | Bit 0 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 0 | Y overflow | X overflow | Y sign | X sign | 1 | middle | right | left |
| 1 | `X[7:0]` | | | | | | | |
| 2 | `Y[7:0]` | | | | | | | |

The displacement of each axis is the 9-bit two's complement value $\{\text{sign}, \text{byte}\}$, from $-256$ to $255$. With the overflow bit of the axis set the displacement is clipped to $255$ or $-256$, by the sign, and the `OVERFLOW` bit turns on.

A first byte with bit 3 clear cannot start a packet. The byte is dropped, the `ERROR` bit turns on and the decoder waits for a new first byte, which resynchronizes the stream. A packet stalled between bytes for `packet_timeout_cycles` clock cycles, or cut by a framing error, is dropped the same way.

### 3.3. Accumulators

Each packet adds its displacement to the accumulator of the axis, which saturates at $-32768$ and $32767$ instead of wrapping. Saturation turns `OVERFLOW` on. Reading `DX` or `DY` delivers the value and clears the accumulator of that axis.

## 4. Interrupt

The `o_irq` output is 1 while the `NEW` bit is on and the enable in `CONTROL` is on. Reading `STATUS` ends the cause. The output is level-sensitive, suited to a PLIC source.

## 5. Channel 1 and the Y cable

The DE0-CV has a single PS/2 connector. With one device it uses channel 0, `PS2_CLK` (pin D3) and `PS2_DAT` (pin G2). For the keyboard and the mouse to work at the same time, a Y cable splits the connector into two ports, and the mouse uses channel 1, `PS2_CLK2` (pin E2) and `PS2_DAT2` (pin G1), which the board manual reserves for this (Table 3-11).

Each channel has its own `ps2_host` and its own peripheral. The instances share no signals or state, so the mouse on channel 1 does not disturb the keyboard on channel 0.

## 6. Integration

### 6.1. Channel connection

In the board top, a `ps2_host` joins the connector lines to the `ps2_mouse` through the byte interface.

| `ps2_host` | `ps2_mouse` | Note |
| :--- | :--- | :--- |
| `i_clk` | `i_clk` | System clock |
| `i_rst_n` | inverse of `i_rst` | The `ps2_host` resets active low and the `ps2_mouse` active high |
| `o_rx_data`, `o_rx_valid`, `o_rx_error` | `i_rx_data`, `i_rx_valid`, `i_rx_error` | Bytes received from the mouse |
| `i_tx_data`, `i_tx_valid` | `o_tx_data`, `o_tx_valid` | Command sent to the mouse |
| `o_tx_ready` | `i_tx_ready` | The transmitter accepts a byte |

`o_tx_valid` is 1 for a single cycle, and only in the cycle where `i_tx_ready` is 1, which suits both a transmitter that takes the byte on the pulse and one that uses the ready and valid handshake.

### 6.2. Top ports and window

| Item | Value |
| :--- | :--- |
| Connector lines (bidirectional ports of the `ps2_host`) | `io_ps2_clk` on pin E2 (`PS2_CLK2`) and `io_ps2_dat` on pin G1 (`PS2_DAT2`) |
| Register window | 8 words (32 bytes), 3-bit word address, five registers used |
| Bus | 32-bit `i_data_in`, `i_address`, `i_write`, `i_read`, `o_data_out`, like the other peripherals |
| Interrupt | `o_irq`, active at 1, for a PLIC source |

### 6.3. Parameters

| Generic | Default | Meaning |
| :--- | :--- | :--- |
| `data_width` | 32 | Width of the data bus |
| `init_timeout_cycles` | 100000000 | Silence accepted during initialization, in clock cycles |
| `packet_timeout_cycles` | 5000000 | Silence accepted in the middle of a packet, in clock cycles |

## 7. Verification

The entity tests drive the byte interface with a model of the `ps2_host` written in the test. They cover the initialization sequence, wrong answers and silence, sending only with the transmitter ready, packets with sign and overflow, accumulation and saturation, resynchronization, framing error and silence in the middle of a packet, the clear on read, the interrupt, reinitialization and the addresses outside the map. The accumulator has its own tests, which include the sum in the same cycle as the clear.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
