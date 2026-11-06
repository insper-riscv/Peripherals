# PLIC

🌐 [Português](../../pt-br/PLIC/plic.md) · [English](../../en/PLIC/plic.md)

## 1. Reference

The PLIC implements the RISC-V Platform-Level Interrupt Controller specification, version 1.0.0 (`riscv-plic-1.0.0`), cut down to one hart and one context, the machine mode one. The specification defines the sources numbered from 1, the priorities, the per-context threshold, claim and complete, and the gateway of each source. The `o_meip` output is the machine external interrupt request (`MEIP`) of the core. The simple `ext_irq_controller` is the fixed-priority alternative, with no priorities or threshold.

## 2. What it is

The PLIC gathers the level interrupt lines of the peripherals and hands the core a single `MEIP`. Each source has a priority, an enable bit and a gateway. The context has a threshold. The core has no supervisor mode, so only context 0 exists.

| Generic | Default | Meaning |
| :--- | :--- | :--- |
| `n_sources` | 8 | Number of sources, 1 to 1023. Source 0 does not exist |
| `priority_bits` | 3 | Width of the priority and of the threshold, 1 to 32. With 3 bits the priorities go from 1 to 7 |
| `addr_width` | 20 | Width of the word address, 20 to 31, given by the window of the platform |

Priority 0 never interrupts. The address window is at least `0x200008` bytes, which matches an `addr_width` of 20. The base and the size of the window come from `platform.yaml`, and `addr_width` is the base-2 logarithm of the window size in words.

## 3. Interface

| Port | Direction | Function |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | Clock and synchronous reset, active at 1 |
| `i_sources` | input | Level lines of the sources, bit $n$ is source $n$, active at 1, synchronous to `i_clk` |
| `i_data_in`, `i_address` | input | 32-bit write data and word address of `addr_width` bits |
| `i_write`, `i_read` | input | Write and read pulses |
| `o_data_out` | output | Read data, combinational on the address |
| `o_meip` | output | `MEIP`, 1 when a candidate source exists |

Reading the claim register has a side effect, and the other reads do not.

## 4. Register map

Accesses are 32 bits wide. The offsets are in bytes from the base of the window, and the word address is the offset divided by 4. An address outside the map reads zero and ignores the write.

| Offset | Register | Access | Reset |
| :--- | :--- | :--- | :--- |
| `0x000000 + 4*id` | Priority of source `id`, `priority_bits` bits | R/W | 0 |
| `0x001000 + 4*k` | Pending of sources $32k$ to $32k+31$ | R | 0 |
| `0x002000 + 4*k` | Context 0 enable of sources $32k$ to $32k+31$ | R/W | 0 |
| `0x200000` | Context 0 threshold, `priority_bits` bits | R/W | 0 |
| `0x200004` | Context 0 claim (read) and complete (write) | R/W | 0 |

Bit 0 of the first pending and enable word is source 0, which does not exist, and reads zero. The same holds for the bits above `n_sources`. The high bits of the priority and of the threshold, above `priority_bits`, read zero.

## 5. Gateway

Each source has a level gateway. When the line is 1 and the source is not being served, the request becomes pending and the source is masked. The pending bit only falls on the claim, even if the line falls first. After the claim the source stays masked until the complete, even if the line stays at 1, so the handler gets one request per service. After the complete, a line still at 1 raises a new request in the next cycle.

## 6. Arbitration, claim and complete

A source is a candidate when it is pending, enabled and its priority is strictly above the threshold. The winner is the candidate of highest priority, and on a tie the lowest identifier wins. So

$$o\_meip = \bigvee_{n=1}^{n\_sources} \left( pend_n \wedge en_n \wedge prio_n > thr \right)$$

Reading the claim returns the identifier of the winner, or 0 with no candidate, and clears its pending bit. A read with no candidate changes nothing. Writing the claim with the identifier of an existing, enabled source unmasks that source. An identifier of 0, outside `1..n_sources`, of a source that is not enabled, or of a source other than the one written changes no gateway. The write does not check that the identifier is the last one claimed, as the specification defines.

## 7. Timing

`o_meip` and the claim read are combinational over the pending, enable, priority and threshold registers, with no path from the `i_sources` inputs to the output. A line that rises shows in `o_meip` one cycle later, when the gateway registers the request.

## 8. Verification

| Check | Coverage |
| :--- | :--- |
| Entity tests `PLIC`, `PlicOneSource`, `PlicWide` and `PlicMax` | Reset, registers with extreme widths (1 source and 1 bit; 70 sources and 8 bits with a larger window; 1023 sources and 32 bits), priority zero, strict threshold, enable, tie by id, complete rules, independent gateways, claim with no candidate, every source and 3000 random cycles against a reference model |
| Entity tests `PlicGateway` and `PlicArbiter` | The gateway against the pending and in-service model, and the arbiter over every pending and enable mask, with random thresholds and priorities |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
