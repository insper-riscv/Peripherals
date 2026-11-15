# Input-only GPIO

🌐 [Português](../../pt-br/GPIO/gpio_input.md) · [English](../../en/GPIO/gpio_input.md)

## 1. What it is

Block of 1 to 32 pins that the FPGA only reads (`gpio_input`). Each pin of `i_pins` is a pure input, with no tristate and no output, and the block hands the processor the synchronized level and an optional interrupt by edge or by level. It serves the pins that the board wires to an external circuit and that Quartus refuses as a bidirectional or output pin, such as the DIP switches, the KEY[1] button and the dedicated input pins `GPIO_*_IN` of the DE0-Nano. On that board the manual (sections 3.2, 3.5 and 3.6) lists these pins as 3.3 V inputs, and Quartus error 169009 refuses the `inout` of the `gpio` block on them.

The block is the `gpio_group` with every pin fixed as an input and without the pin driver ports, so the register map and the C driver of `gpio` apply unchanged.

## 2. Interface

### 2.1. Generics

| Generic | Default | Description |
| :--- | ---: | :--- |
| `width` | 32 | Number of pins, from 1 to 32 |
| `active_low` | zeros | Bit $p$ at 1 marks pin $p$ as active low; the program reads the inverted level |

### 2.2. Ports

| Port | Direction | Description |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | Clock and synchronous reset, active at 1 |
| `i_data_in`, `o_data_out` | input and output, `word_t` | Bus data; the read is combinational on the address |
| `i_address` | input, 4 bits | Word address inside the block |
| `i_write`, `i_read` | input | Write and read pulses |
| `o_irq` | output | Reads 1 while any pin has a pending event |
| `i_pins` | input, `width` bits | Level of the physical pins, asynchronous |

## 3. Registers

The block takes 16 words (a 64-byte window), the same as a `gpio` group, and the bits above `width` read zero.

| Word | Name | Read | Write |
| ---: | :--- | :--- | :--- |
| 0 | `DIR` | Zero, the direction is fixed as input | Ignored |
| 1 to 4 | `OUT_*` | The value written, which reaches no pin | Stored |
| 5 | `IRQ_MASK` | Global mask per pin | Sets the mask |
| 6 | `RISE_MASK` | Rising mask | Sets the mask |
| 7 | `FALL_MASK` | Falling mask | Sets the mask |
| 8 | `IRQ_STAT` | Pin with a pending interrupt | The read clears the bits read |
| 9 | `PINS` | Synchronized pins, with the polarity applied | Ignored |
| 10 | `LEVEL_MASK` | Level mode per pin | Sets the mode |
| 11 to 15 | | Zero | Ignored |

## 4. Input and interrupt

Each pin goes through a two-stage synchronizer, and `PINS` reads the value after it, two cycles of `i_clk` after the pin. The interrupt condition of each pin depends on `LEVEL_MASK`, `RISE_MASK` and `FALL_MASK`, as in `gpio`, and it only reaches `IRQ_STAT` and `o_irq` with the pin bit set in `IRQ_MASK`. With all masks at zero, the reset value, the block only delivers the pin levels and no interrupt leaves.

| `LEVEL_MASK` | `RISE_MASK` | `FALL_MASK` | Pin condition |
| :--- | :--- | :--- | :--- |
| 0 | 1 | 0 | Rising edge of the synchronized input |
| 0 | 0 | 1 | Falling edge |
| 0 | 1 | 1 | Any change |
| 1 | 1 | 0 | High level |
| 1 | 0 | 1 | Low level |
| 1 | 1 | 1 | Always |

On an active-low pin the conditions apply to the logic level after the inversion, so the logic rising edge is the electrical falling edge.

## 5. Verification

The entity tests cover the read of `DIR`, the synchronization of `PINS`, rising and falling edges on distinct pins, the level mode, the clearing of `IRQ_STAT` by the read and the polarity of active-low pins. The group the block instantiates has the formal proofs of `gpio`.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
