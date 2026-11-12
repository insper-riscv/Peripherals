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

Construct instances with `rv32_gpio_new(base, pin_count)`. Constructors allocate
no memory and do not configure hardware. Invalid arguments produce an invalid
handle, checked with `rv32_gpio_valid`. Do not initialize handle structs directly.
Pin count comes from the RTL instance, not the MMIO window size.

```c
rv32_gpio_t gpio = rv32_gpio_new(RV32_GPIO_SWITCHES_BASE, 10);

rv32_gpio_pin_direction(gpio, 3, RV32_GPIO_OUTPUT_PIN);
rv32_gpio_pin_write(gpio, 3, true);
rv32_gpio_pin_toggle(gpio, 3);
```

Pins are zero-based `size_t` indices. The driver checks bounds and builds
`1u << pin` internally: pin 3 selects mask `0x08`, not address `0x03`.
Set/clear/toggle use atomic hardware registers. Direction/IRQ configuration
preserves other bits but callers must serialize configuration. The previous
whole-mask API remains available for grouped operations.

Pin reads return the currently synchronized value without waiting. Tests that
write and observe a pin use bounded condition polling, not arbitrary `settle()`
delays in every operation. Reading IRQ status clears ALL instance events;
`rv32_gpio_irq_contains(snapshot, pin)` interprets that snapshot without exposing
masks to application code. Persistent level conditions can raise another event.

The SDK vendors the reusable sources into `vendor/GPIO` and resolves instance
base addresses from `platform.yaml`. Internal register offsets follow the RTL
and remain in the C implementation. One driver serves GPIO, SWITCHES and KEYS.

Constructor-based drivers now cover GPIO, TIMER, CLINT, PLIC, UART (serial/JTAG),
DISPLAY and FLASH. CLINT performs coherent 64-bit reads and safe deadline writes;
PLIC takes source numbers (zero reserved); DISPLAY takes digit indices. UART
requires the actual backend and TX capacity. FLASH uses buffer word indices,
named commands and W1C IRQ acknowledgement. Each header documents side effects.

Run `make driver-test` for RAM-backed MMIO and `make test` for RTL behavior.
RAM does not model read-to-clear, W1C, FIFO state or pin propagation.

Use `.clang-format`: four-space indentation, multiline functions, one statement
per line and blank lines between functions and logical blocks.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
