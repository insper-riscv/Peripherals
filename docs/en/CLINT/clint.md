# CLINT

🌐 [Português](../../pt-br/CLINT/clint.md) · [English](../../en/CLINT/clint.md)

## 1. What it is

The CLINT is the machine timer of one hart, memory-mapped in the layout of the SiFive CLINT that the official FreeRTOS port expects. It provides the 64-bit `mtime`, the 64-bit `mtimecmp` and the `msip`, and raises the machine timer (`MTIP`) and machine software (`MSIP`) interrupts.

| Parameter | Default | Meaning |
| :--- | :--- | :--- |
| `tick_cycles` | 1 | Clock cycles per `mtime` increment |

The general-purpose `TIMER` remains an independent peripheral. The `mtime` of the CLINT is its own counter, at the clock frequency divided by `tick_cycles`, and the `time` CSR of the core is its read-only shadow, through the `o_mtime` output.

## 2. Interface

Besides the common peripheral ports, the CLINT has two interrupt outputs. The address is 14 word bits, which covers the 64 KiB of the map. The CLINT has no `i_read`, because a read has no side effect and `o_data_out` is combinational on the address.

| Port | Direction | Function |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | Clock and reset, active at 1 |
| `i_data_in`, `i_address` | input | 32-bit write data and 14-bit word address |
| `i_write` | input | Write pulse |
| `o_data_out` | output | Read data, combinational on the address |
| `o_irq_timer` | output | `MTIP` |
| `o_irq_software` | output | `MSIP` |

## 3. Register map

Every access is 32 bits wide, little-endian, with the low half at the lower address. An address outside the map reads zero and ignores writes.

| Offset | Register | Access | Reset |
| :--- | :--- | :--- | :--- |
| `0x0000` | `msip` (bit 0) | R/W | 0 |
| `0x4000` | `mtimecmp` low | R/W | `0xFFFFFFFF` |
| `0x4004` | `mtimecmp` high | R/W | `0xFFFFFFFF` |
| `0xBFF8` | `mtime` low | R/W | 0 |
| `0xBFFC` | `mtime` high | R/W | 0 |

Only bit 0 of `msip` is stored, and the other bits read zero.

## 4. Counting and reading `mtime`

Every `tick_cycles` cycles the `mtime` adds 1. The low half adds 1 and, when it was all ones, the carry is registered and the high half adds 1 in the next cycle, so no 64-bit addition sits on a combinational path. In the cycle with a pending carry, a read of the high half returns the stored high half plus the carry, so the pair read is always the value of the ideal 64-bit counter.

The three-step read of the port (high, low, high) repeats until both high halves match, and the result is coherent. A write of the low half wins over the increment of its own cycle, and a write of the high half drops the pending carry.

## 5. Comparison and `MTIP`

$$MTIP_{t+1} = \left( mtime_t \ge mtimecmp_t \right)$$

The comparison is unsigned, 64 bits wide, and the result goes through a one-cycle register. After reset the `mtimecmp` is all ones and `MTIP` is low. The `MSIP` output is bit 0 of `msip`.

## 6. Safe `mtimecmp` write

The FreeRTOS port writes `mtimecmp` in three 32-bit writes.

| Step | Write | Value of `mtimecmp` afterwards |
| :--- | :--- | :--- |
| 1 | Low half with `0xFFFFFFFF` | $\{hi_{old}, \mathtt{0xFFFFFFFF}\} \ge$ old value |
| 2 | High half with the final value | $\{hi_{final}, \mathtt{0xFFFFFFFF}\} \ge$ final value |
| 3 | Low half with the final value | Final value |

Each intermediate state is greater than or equal to the old value or the final one, and with a growing $mtime$ this guarantees that `MTIP` does not rise in the middle of the sequence unless the old or the final value would have raised it. Writing the low half first with the final value has no such guarantee, and raises an interrupt that is not due yet when the old high half is smaller than the final one.

## 7. Verification

| Check | Coverage |
| :--- | :--- |
| Entity tests `CLINT`, `ClintTick` and `ClintMtime` | Reset, counting, carry with the three-step read, 64-bit comparison, equality, the port write sequence with no spurious `MTIP`, drop of a pending `MTIP`, `msip`, unmapped addresses, the cycle divider and the counter against a random model |
| Formal proofs `clint` and `clint_mtime` | The outputs and the read of every address follow the ideal model; in the port write sequence `MTIP` holds only if the old or the final value was reached; covers of `MTIP` rising and falling, of `MSIP` and of the carry |

The mutants and the method are in [formal.md](../formal/formal.md).

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
