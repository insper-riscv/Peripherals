# Seven-segment display (`seg_display`)

🌐 [Português](../../pt-br/display/seg_display.md) · [English](../../en/display/seg_display.md)

## 1. What it is

A register that holds 4 bits per digit and shows them in hexadecimal on the seven-segment displays, through the `hex_to_seg7` converter. The value stays in the register between two programs, and the host reads and writes it over the JTAG chain, alongside the core.

## 2. Generics

| Generic | Default | Effect |
| :--- | :--- | :--- |
| `digits` | 6 | Number of digits, from 0 to 8. The register has `4 * digits` bits and `o_hex` has `7 * digits` bits. Zero leaves the module with no register and no segment |
| `active_low` | true | Segments lit at the low level, as on the DE boards. False lights them at the high level |

The polarity is only on the `o_hex` output. The converter lights at the low level and the generic picks the pin level, so the rest of the module does not depend on the board.

## 3. Core side

One access per pulse of `i_we` or `i_re`. Word 0 reads the `4 * digits`-bit value and the write stores the low `4 * digits` bits. The other words read zero and ignore the write.

## 4. Host side

Virtual JTAG instruction 1 selects a register of `4 * digits + 1` bits. The low bits are the new value and the top bit stores the value when it is 1. The output carries the register value at the start of the scan. Instruction 2 selects the 2-bit failure flag register, which only the host and the FPGA reconfiguration change. The host write crosses to the core clock through a toggle and two flip-flops, and the core wins when both write in the same cycle.

## 5. Verification

The entity tests cover the pattern of each digit, the core and host access, the three-digit variant with active-high segments (12-bit register and 13-bit scan) and the zero-digit module, which stores nothing and reads zero.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
