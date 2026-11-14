# GPIO

🌐 [Português](../../pt-br/GPIO/gpio.md) · [English](../../en/GPIO/gpio.md)

## 1. What it is

A general-purpose I/O block with an adaptive partition. The block gathers `pin_count` bidirectional pins into `group_count` groups, and each group has its own 64-byte register file (`gpio_group`), with direction, output, synchronized input and per-pin interrupt configuration. The partition, the fixed direction and the polarity of each pin come from generics, so the same entity serves one LED per group (`solo`), all the switches in a single register (`all`) or a hand-written partition. The whole block uses a single interconnect window.

| Entity | Role |
| :--- | :--- |
| `gpio` | The block, with the partition, the group selector, the read path and the physical pins |
| `gpio_group` | The register file of a group of 1 to 32 pins |
| `gpio_cell` | One pin, with direction, output, synchronized input and interrupt |
| `gpio_operation_decoder` | The word address of a group into write enables and a read selector |
| `gpio_pkg` | Elaboration functions that read the lists of the generics |

## 2. Interface of the `gpio` block

### 2.1. Generics

A vector of numbers has one 8-bit field per element, with element $k$ in bits $8k+7$ to $8k$ (element 0 is the least significant field). The generics use only integers and `std_logic_vector`, with no VHDL-2008 type and no generic package.

| Generic | Type | Default | Encoding |
| :--- | :--- | :--- | :--- |
| `pin_count` | `positive` from 1 to 255 | 32 | Pins of the block, numbered 0 to `pin_count - 1` |
| `group_count` | `positive` from 1 to 255 | 1 | Number of groups $G$ |
| `member_count` | `positive` from 1 to 255 | 32 | Total of indices listed in `group_members`, equal to the sum of the sizes |
| `group_sizes` | `std_logic_vector(8 * group_count - 1 downto 0)` | `x"20"` | Field $g$ is the number of pins of group $g$, from 1 to 32 |
| `group_members` | `std_logic_vector(8 * member_count - 1 downto 0)` | pins 0 to 31 | Pin indices of all groups in sequence, in the written order; bit $k$ of the registers of a group is the $k$-th pin of the list of that group |
| `pin_dirs` | `std_logic_vector(2 * pin_count - 1 downto 0)` | zeros | Code of pin $p$ in bits $2p+1$ to $2p$ |
| `pin_active_low` | `std_logic_vector(pin_count - 1 downto 0)` | zeros | Bit $p$ at 1 is an active-low pin |

| Code in `pin_dirs` | Direction of the pin |
| :--- | :--- |
| `00` | Free, the `DIR` register decides |
| `01` | Fixed as input |
| `10` | Fixed as output |
| `11` | Refused at elaboration |

The widths of the vectors depend on the generics before them, so whoever instantiates the block passes every generic and writes each vector with the width the other generics impose. The example below is the partition `[[0,1,2,3],[5,6]]` of a role with 7 pins, all free and active high, with pin 4 off.

```vhdl
u_leds : entity work.gpio
    generic map (
        pin_count      => 7,
        group_count    => 2,
        member_count   => 6,
        group_sizes    => x"02" & x"04",
        group_members  => x"06" & x"05" & x"03" & x"02" & x"01" & x"00",
        pin_dirs       => (others => '0'),
        pin_active_low => (others => '0')
    )
```

The concatenation lists the last element first, because element 0 is the least significant field.

### 2.2. Ports

| Port | Direction | Type | Function |
| :--- | :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | `std_logic` | Clock and reset, active at 1 |
| `i_data_in` | input | `word_t` | Write data |
| `i_address` | input | `std_logic_vector(block_addr_width(group_count) - 1 downto 0)` | Word address inside the window |
| `i_write`, `i_read` | input | `std_logic` | Write and read pulses |
| `o_data_out` | output | `word_t` | Read data, combinational on the address |
| `o_irq` | output | `std_logic` | 1 while any group has a pending interrupt |
| `io_gpio_pins` | inout | `std_logic_vector(pin_count - 1 downto 0)` | Physical pins |

## 3. Window and address

The register file of each group takes 64 bytes, and group $g$ starts at $64g$ bytes from the base of the block. The block takes a window of

$$
W = 2^{\lceil \log_2 (64 \cdot G) \rceil}
$$

bytes, which is $64 G$ rounded up to the next power of two. The width of the word address is

$$
\text{block\_addr\_width}(G) = 4 + \lceil \log_2 G \rceil
$$

bits, where the 4 low bits pick the word of the group and the high bits pick the group. The interconnect hits the block when `(addr and not (W - 1)) = base`, with `base` aligned to $W$, and hands the block the byte address without its 2 low bits. A group that does not exist (an index greater than or equal to $G$ inside the window) reads zero and ignores writes.

| $G$ | Window $W$ | Width of `i_address` |
| ---: | ---: | ---: |
| 1 | 64 B | 4 |
| 2 | 128 B | 5 |
| 3 and 4 | 256 B | 6 |
| 10 | 1 KiB | 8 |
| 18 | 2 KiB | 9 |

## 4. Registers of a group

Each group has 16 words. The bits above the size of the group read zero and ignore writes. A word outside the table reads zero and ignores writes.

| Word | Name | Read | Write |
| ---: | :--- | :--- | :--- |
| 0 | `DIR` | Direction of each pin, 1 is output; fixed-direction pins read the fixed value | Sets the direction of the free pins |
| 1 | `OUT_LOAD` | Output register | Loads the whole word |
| 2 | `OUT_SET` | Output register | Sets the bits written as 1 |
| 3 | `OUT_CLR` | Output register | Clears the bits written as 1 |
| 4 | `OUT_TGL` | Output register | Toggles the bits written as 1 |
| 5 | `IRQ_MASK` | Global mask per pin | Sets the mask |
| 6 | `RISE_MASK` | Rising-edge mask per pin | Sets the mask |
| 7 | `FALL_MASK` | Falling-edge mask per pin | Sets the mask |
| 8 | `IRQ_STAT` | Pin with a pending interrupt | The read clears the bits read |
| 9 | `PINS` | Synchronized pins | Ignored |
| 10 | `LEVEL_MASK` | Level mode per pin | Sets the mode |
| 11 to 15 | | Zero | Ignored |

## 5. Pin that is off

A pin that is in the list of no group is off, with no register, no read and no interrupt.

| Direction of the pin that is off | Level of the physical pin |
| :--- | :--- |
| Fixed as output | Held at the inactive level, which is 0 for an active-high pin and 1 for an active-low pin |
| Free or fixed as input | High impedance |

## 6. Interrupt

Each pin has its pending bit in `IRQ_STAT`, which turns on when the condition of the pin holds and `IRQ_MASK` is on. `o_irq` is 1 while any pending bit of any group is on. Reading `IRQ_STAT` of a group clears only the bits of that group. The events of a pin depend on its bit in `LEVEL_MASK`.

| `LEVEL_MASK` | `RISE_MASK` | `FALL_MASK` | Condition of the pin |
| :--- | :--- | :--- | :--- |
| 0 | 1 | 0 | Rising edge of the synchronized input |
| 0 | 0 | 1 | Falling edge |
| 0 | 1 | 1 | Any change |
| 1 | 1 | 0 | High level |
| 1 | 0 | 1 | Low level |
| 1 | 1 | 1 | Always (any level) |

In level mode the pending bit turns on again every cycle while the level holds, so reading `IRQ_STAT` does not end the cause. Software disables the mask of the pin or removes the level at its source. All the mask registers and the mode are zero after reset.

## 7. Polarity and fixed direction

With the bit of `pin_active_low` at 1, the `gpio_cell` inverts both senses of the pin. The pin that is read is inverted before the synchronizer, so `PINS`, the edges and the levels hold for the program active at 1, and the output register is inverted before the tristate. The program always sees and writes active at 1.

On a fixed-direction pin the internal direction register still takes the write, but the effective value is the fixed one, which `DIR` reads and which enables or releases the tristate. A pin fixed as output stays driven at all times, reset included.

## 8. Verification

The entity tests cover the partitions `solo`, `pairs`, explicit (`[[0,1,2,3],[5,6]]` with one pin off), a group with the order of its pins reversed, `all`, a mixed block with fixed directions, polarities and an output pin that is off, the cell with a fixed direction and the group of 32 pins. The formal proof of the block (`gpio_props.sv`) compares the read of `DIR` and `OUT`, the read of the addresses without a register and the value driven on each pin with an ideal model, in two partitions, and the proof of the cell (`gpio_cell_props.sv`) includes the polarity, the level mode and both fixed directions, each with its mutants.

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

In the block with several groups, each group has its own 64-byte register file, and `rv32_gpio_group_new(base, group, group_pins)` returns the handle of group `group`. The pin index of the handle is the position of the pin in the list of the group. The same holds for the display, with `rv32_display_group_new(base, group, group_digits)`.

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
