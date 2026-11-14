# Seven-segment display (`seg_display`)

🌐 [Português](../../pt-br/display/seg_display.md) · [English](../../en/display/seg_display.md)

## 1. What it is

A register that holds 4 bits per digit and shows them in hexadecimal on the seven-segment displays, through the `hex_to_seg7` converter. The value stays in the register between two programs, and the host reads and writes it over the JTAG chain, alongside the core.

## 2. Generics

| Generic | Default | Effect |
| :--- | :--- | :--- |
| `digits` | 6 | Number of digits, from 0 to 8. The register has `4 * digits` bits and `o_hex` has `7 * digits` bits. Zero leaves the module with no register and no segment |
| `active_low` | true | Segments lit at the low level, as on the DE boards. False lights them at the high level |
| `group_count` | 1 | Number of digit groups, from 1 to 8 |
| `member_count` | 6 | Total of digit indices listed in `group_members`, equal to the sum of the sizes |
| `group_sizes` | `x"06"` | `std_logic_vector(8 * group_count - 1 downto 0)`; field $g$ is the number of digits of group $g$ |
| `group_members` | digits 0 to 5 | `std_logic_vector(8 * member_count - 1 downto 0)`; digit indices of all groups in sequence, in the written order |
| `has_dp` | false | Eight-segment digits, with the decimal point. True makes `o_hex` `8 * digits` bits wide and enables word 1 of each group (section 6); false keeps `7 * digits` bits and the behavior without a point |

The fields of the lists have 8 bits, with element $k$ in bits $8k+7$ to $8k$, like the partition generic of the GPIO (`docs/en/GPIO/gpio.md`). A digit that is in the list of no group is blank, with every segment at the inactive level of the board, and `o_value` keeps its 4 bits for the host.
The polarity is only on the `o_hex` output. The converter lights at the low level and the generic picks the pin level, so the rest of the module does not depend on the board.

## 3. Interface

The ports follow the bus of the other peripherals, with `o_rdata` as the read output. The read is combinational on the address, so there is no read pulse.

| Interface | Port | Direction | Function |
| :--- | :--- | :--- | :--- |
| Control | `i_clk`, `i_rst` | input | Core clock and synchronous reset, active at 1 |
| Bus | `i_address` | input | 8-bit word offset inside the window |
| Bus | `i_data_in`, `i_write` | input | `word_t` write data (`XLEN` bits) and write pulse |
| Bus | `o_rdata` | output | `word_t` read data (`XLEN` bits), combinational on the address |
| JTAG | `i_tck`, `i_tdi`, `o_tdo` | input, input, output | Clock and serial data of the Virtual JTAG chain |
| JTAG | `i_ir_in` | input | 2-bit instruction register |
| JTAG | `i_state_cdr`, `i_state_sdr`, `i_state_udr`, `i_state_uir` | input | Capture-DR, Shift-DR, Update-DR and Update-IR states |
| Board | `o_value` | output | Stored value, `4 * digits` bits |
| Board | `o_fail` | output | Failure flag written by the host |
| Board | `o_hex` | output | Segments, `7 * digits` bits (`8 * digits` with `has_dp`), with the polarity of `active_low` |
| Board | `o_dp` | output | Stored point bit of each digit, `digits` bits, 1 = lit; zero without `has_dp` |

## 4. Core side

One access per pulse of `i_write`. Each group has a 64-byte window, and group $g$ starts at word $16g$ of the word address. Word 0 of the group holds its digits, and digit $k$ of the list of the group takes bits $4k+3$ to $4k$. The read returns the digits of the group, and the write stores only the digits of the group, without touching the others. The other words of the group, and the groups that do not exist, read zero and ignore the write. The block takes a window of $64 G$ bytes rounded up to the next power of two, like the GPIO, and `i_address` is 8 bits wide.

## 5. Host side

Virtual JTAG instruction 1 selects a register of `4 * digits + 1` bits. The low bits are the new value and the top bit stores the value when it is 1. The output carries the register value at the start of the scan. Instruction 2 selects the 2-bit failure flag register, which only the host and the FPGA reconfiguration change. The host write crosses to the core clock through a toggle and two flip-flops, and the core wins when both write in the same cycle.

## 6. Decimal point

With `has_dp` true, each digit of `o_hex` has 8 bits. Digit $n$ takes bits $8n+7$ to $8n$, with the seven segments `gfedcba` in the low bits and the point in bit 7, like `HEXn[7]` of the DE10-Lite. The point bit of each digit of the group is in word 1 of the group (word $16g+1$), with digit $k$ of the list of the group in bit $k$ and 1 for a lit point. Word 0 keeps the format of section 4, so a program that writes only digits does not change.

| Group word | `has_dp` false | `has_dp` true |
| :--- | :--- | :--- |
| 0 | Digits, nibble $k$ at bit $4k$ | Same |
| 1 | Reads zero, ignores the write | Points, bit $k$ = point of digit $k$ of the group; the bits above the size of the group read zero and ignore the write |
| 2 to 15 | Reads zero, ignores the write | Reads zero, ignores the write |

The point register belongs to the core only. The host over JTAG neither reads nor writes it, and the FPGA reconfiguration and the reset clear it. A digit in no group has no point bit and is fully blank, point included. The point polarity is that of `active_low`, the same as the seven segments, and `o_dp` mirrors the register without polarity for the integration.

Of the boards in the manuals, only the DE10-Lite has the eighth segment (section 3.4, table 3-6, signals `HEX07`, `HEX17`, `HEX27`, `HEX37`, `HEX47` and `HEX57`). The DE0-CV (section 3.3) and the DE2-115 (section 4.4) list only `HEXn[6:0]`.

### 6.1. C example

The example lights the point of digit 2 of group 0 and shows the value `0x1234` on the first four digits. `base` is the byte address of the `seg_display` window in the SoC and each group takes 64 bytes.

```c
#include <stdint.h>

#define SEG_GROUP_BYTES 64u
#define SEG_WORD_DIGITS 0u
#define SEG_WORD_DOTS   1u

static volatile uint32_t *seg_word(uintptr_t base, unsigned group, unsigned word)
{
    return (volatile uint32_t *)(base + group * SEG_GROUP_BYTES + word * 4u);
}

void seg_show(uintptr_t base)
{
    /* Digit k of group 0 in nibble k: 0x1234 shows as "1234" from right to left. */
    *seg_word(base, 0, SEG_WORD_DIGITS) = 0x1234u;
    /* Bit k = point of digit k of group 0; here only digit 2 has its point lit. */
    *seg_word(base, 0, SEG_WORD_DOTS) = 1u << 2;
}

void seg_dot_off(uintptr_t base)
{
    *seg_word(base, 0, SEG_WORD_DOTS) = 0u;
}
```

## 7. Verification

The entity tests cover the pattern of each digit, the core and host access, the decimal point (eight digits in two groups with blank digits, three active-high digits, a lit and a cleared point, digits outside any group, the reset and the host having no effect on the point, and the default without `has_dp` with a silent word 1),  the three-digit variant with active-high segments (12-bit register and 13-bit scan) and the zero-digit module, which stores nothing and reads zero, and the partitions with a single digit, an explicit one (`[[0,1,2,3],[5,6]]` over 8 digits) and one with the digits in reverse order. The formal proof (`seg_display_props.sv`) compares the read, the stored value, the points and the segments of every digit with an ideal model, in four partitions (A and B without a point, C and D with `has_dp`), and five point mutants are caught.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
