# External interrupt controller

## 1. What it is

The controller gathers the level-sensitive interrupt lines of the peripherals into a single external interrupt request, the core's `MEIP`. Software reads the state of the lines, chooses which of them count and finds out which one is active, all through 32-bit registers on the same bus as the other peripherals. There is no programmable priority, threshold or claim: the interrupt is level sensitive and software clears the cause in the source peripheral.

| Item | Value |
| :--- | :--- |
| Entity | `ext_irq_controller` |
| Lines | `irq_count`, from 1 to `data_width` (8 by default) |
| Synchronization | `sync_stages` flip-flops per line (2 by default), through the Common-Components `synchronizer` |
| Mapped access | Combinational read and 1-cycle write, no bus wait |
| Output | `o_irq_external`, active at `1` |

## 2. Registers

The address has 2 bits and counts words. The values are in the `ext_irq_consts` package.

| Word | Name | Read | Write |
| ---: | :--- | :--- | :--- |
| 0 | `PENDING` | Bit $n$ is line $n$, already synchronized | Ignored |
| 1 | `ENABLE` | Bit $n$ enables line $n$ | Stores the bits of the existing lines |
| 2 | `SOURCE_ID` | Index of the lowest active line plus one, or zero | Ignored |
| 3 | reserved | Zero | Ignored |

Bits above the last line read zero and are not stored. `ENABLE` is zero after reset, and reading any register has no side effect.

## 3. Behavior

Let $p$ be the `PENDING` vector and $e$ the `ENABLE` vector. The output is

$$o\_irq\_external = \big( (p \wedge e) \ne 0 \big)$$

and follows the lines after the synchronizer latency of `sync_stages` cycles. Because the interrupt is level sensitive, the output falls when the line falls, with no latch.

`SOURCE_ID` is $k + 1$, where $k$ is the lowest index with $p_k \wedge e_k = 1$, and zero when there is none. The lowest-index line always wins, and the added one keeps zero meaning "no source".

## 4. Wiring

1. Each peripheral with an interrupt output (for example `o_irq` of the `TIMER`, the `GPIO` and the `UART`) connects to one line of `i_irq_lines`.
2. `o_irq_external` connects to the core's `MEIP` port, and software enables the interrupt in `mie` (`MEIE`).
3. The handler reads `SOURCE_ID` to know which peripheral to serve, clears the cause there and returns.

## 5. Verification

| Check | File | What it covers |
| :--- | :--- | :--- |
| Entity test | `tests/python/unittests/intc/ext_irq_controller.py` | Reset, each line with the synchronizer latency, mask, `ENABLE` read-back, level output, several sources and `SOURCE_ID`, ignored writes, side-effect-free reads and reset |
| Formal proof | `formal/ext_irq_controller_props.sv` | Bounded, 12 cycles, 4 lines: the output is exactly $(p \wedge e) \ne 0$, each address returns the right register and `SOURCE_ID` is the lowest active line plus one |

The cover shows that two active sources, a single one and a masked pending line are reachable. The mutants `extirq_mask_ignored`, `extirq_or_not_and`, `extirq_write_any_address`, `extirq_enable_not_reset`, `extirq_highest_wins`, `extirq_id_zero_based`, `extirq_pending_is_enable` and `extirq_reserved_reads_id` must make the proof fail.
