# GPIO

🌐 [Português](../../pt-br/GPIO/gpio.md) · [English](../../en/GPIO/gpio.md)

## 1. What it is

A general-purpose I/O block with `data_width` bidirectional pins; `data_width` zero is allowed and leaves the block with no pin, no register and no interrupt. Each pin is a `gpio_cell` with direction, output, synchronized input and per-pin interrupt configuration. The `gpio_operation_decoder` turns the word address into the write enables and the read selector.

## 2. Registers

The address is a 4-bit word address. An address outside the table reads zero and ignores writes.

| Word | Name | Read | Write |
| ---: | :--- | :--- | :--- |
| 0 | `DIR` | Direction of each pin, 1 is output | Sets the direction |
| 1 | `OUT_LOAD` | Output register | Loads the whole word |
| 2 | `OUT_SET` | Output register | Sets the bits written as 1 |
| 3 | `OUT_CLR` | Output register | Clears the bits written as 1 |
| 4 | `OUT_TGL` | Output register | Toggles the bits written as 1 |
| 5 | `IRQ_MASK` | Global mask per pin | Sets the mask |
| 6 | `RISE_MASK` | Rise mask per pin | Sets the mask |
| 7 | `FALL_MASK` | Fall mask per pin | Sets the mask |
| 8 | `IRQ_STAT` | Pins with a pending interrupt | The read clears the bits read |
| 9 | `PINS` | Synchronized pins | Ignored |
| 10 | `LEVEL_MASK` | Level mode per pin | Sets the mode |

## 3. Interrupt

Each pin has its pending bit in `IRQ_STAT`, which sets when the pin condition holds and `IRQ_MASK` is on. The `o_irq` output is 1 while any pending bit is set. The events of a pin depend on its bit in `LEVEL_MASK`.

| `LEVEL_MASK` | `RISE_MASK` | `FALL_MASK` | Pin condition |
| :--- | :--- | :--- | :--- |
| 0 | 1 | 0 | Rising edge of the synchronized input |
| 0 | 0 | 1 | Falling edge |
| 0 | 1 | 1 | Any change |
| 1 | 1 | 0 | High level |
| 1 | 0 | 1 | Low level |
| 1 | 1 | 1 | Always (any level) |

In level mode the pending bit sets again every cycle while the level holds, so reading `IRQ_STAT` does not end the cause. Software disables the pin mask or removes the level at its source. Every mask register and the mode are zero after reset, which keeps the edge behavior of the earlier maps.

## 4. Polarity

The `active_low` generic (default false) inverts both directions of the pin inside the `gpio_cell`. The pin read is inverted before the synchronizer, so `PINS`, the edges and the interrupt levels hold for the program active at `1`, and the output register is inverted before the tri-state buffer. The program always sees and writes active at `1`, and the top only picks the generic according to the board.

## 5. Verification

Entity tests of the decoder, the cell and the block cover the map, the edges, the per-pin level mode and the zero read of addresses outside the map. The formal proof of the cell (`gpio_cell_props.sv`) includes the level mode, the `active_low` polarity and the mutants of each. The tests also cover the block with `active_low` and the zero-width block.

## 6. C23 driver

The driver in `src/GPIO/soc/driver/c/` accepts a base address per instance. The SDK generator copies its sources into `vendor/GPIO` and generates addresses from the platform map. The descriptor maps GPIO, SWITCHES and KEYS to one implementation.

Direction 1 means output. Set, clear and toggle use a single mask write. Reading IRQ status returns and clears all pending events for that instance, without a W1C write. A persistent level may raise another event. Direction and IRQ configuration replace complete masks and require callers to serialize concurrent changes.

Run `make driver-test` to check C accesses against RAM-backed MMIO and `make test TEST=GPIO` to check RTL effects.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
