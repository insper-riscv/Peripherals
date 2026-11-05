# Formal verification

🌐 [Português](../../pt-br/formal/formal.md) · [English](../../en/formal/formal.md)

The formal proofs run in SymbiYosys on the Verilog netlist that GHDL synthesizes from each entity, with the properties written in SystemVerilog around it (`formal/<entity>_props.sv`). The method, the engines (`yices`, `bitwuzla`, `boolector` and `abc-bmc3`), the `build/formal/result-<engine>.tsv` file and the rule of the `formal/aggregate.sh` aggregator are the Core's. This document describes what is proved on the peripherals.

## 1. What is proved

| Entity | File | Proof | Properties |
| :--- | :--- | :--- | :--- |
| `alu_ge_unsigned` | `alu_ge_unsigned_props.sv` | induction, 8 bits | `o_ge` is exactly unsigned `a >= b`, on equality and at the extremes too |
| `counter_overflow` | `counter_overflow_props.sv` | induction, 8 bits | The overflow holds exactly when the counter reached the top |
| `clock_prescaler` | `clock_prescaler_props.sv` | bounded, 40 cycles, 3 bits | With a stable prescaler $P$ and no reset, the tick comes every $P + 1$ cycles, none lost or doubled, and lasts one cycle |
| `timer` | `timer_props.sv` | induction | The configuration, top, duty cycle and prescaler registers change only by a bus write (and the reset takes them to the initial value, top all ones); the counter only clears, loads or advances one per tick with the start on, and stops or restarts at the top according to the mode; the status rises once per overflow, is cleared by the read and the mask decides the interrupt; the PWM is high while the counter is below the duty cycle; the read of each address returns the right register |
| `gpio_cell` | `gpio_cell_props.sv` | bounded, 16 cycles | Direction, output and masks change only by a write (set, clear and toggle with the bit mask); the pin read is the pin from two cycles ago; the status rises on the edge the masks select and falls only by a read or a reset; with the output on and steady the read and the output do not diverge |
| `uart` | `uart_props.sv` | induction and bounded, 200 cycles | Wrapper registers against the contract (valid, overrun, dropped, mask, read of each address); no byte is lost with the buffer free; transmit frame with start, eight data bits from the least significant and stop, 16 cycles per bit; receive of a frame with noise at the edges of each data bit, sampled mid-bit |

Each entity has a cover that shows the proved situation is reachable.

## 2. How each proof is built

1. The netlist of the `timer` and the `uart` has the internal registers exposed as `dbg_*` outputs, which lets the induction state the invariants without changing the logic.
2. In the `gpio_cell` the bidirectional pin of the netlist becomes an input and an output, and the environment drives the pin only when the direction is input.
3. In the `uart` the baud generator runs with `baud_freq = 0` and `baud_limit = 0`, which makes `ce16` hold on every cycle and a bit last 16 cycles. The real ratios only change how long `ce16` takes to arrive, not the frame format nor the sampling point in `ce16` cycles.
4. The `clock_prescaler` uses 3 bits and any constant prescaler; the `timer` uses the prescaler `tick` as an input of the model, because the tick period is the property of the `clock_prescaler`. Together the two proofs fix the pace of the overflow: the counter advances one per tick and the tick comes every $P + 1$ cycles.

## 3. Mutants

Each deliberate defect of the VHDL must make a proof fail. `formal/run.sh` applies each edit with `sed` to a copy of the file and requires the `fail` verdict.

| Entity | Mutants |
| :--- | :--- |
| `alu_ge_unsigned` | `alu_strict`, `alu_no_invert` |
| `counter_overflow` | `ovf_swapped`, `ovf_strict` |
| `clock_prescaler` | `presc_unregistered`, `presc_strict`, `presc_no_clear` |
| `timer` | `timer_top_enable`, `timer_prescaler_enable`, `timer_top_reset`, `timer_mode_inverted`, `timer_start_ignored`, `timer_mask_ignored`, `timer_status_not_cleared`, `timer_level_not_edge`, `timer_pwm_inverted`, `timer_read_select`, `timer_write_address` |
| `gpio_cell` | `cell_dir_always`, `cell_no_set_clear`, `cell_toggle_is_load`, `cell_mask_ignored`, `cell_fall_uses_rise`, `cell_status_not_cleared`, `cell_pin_not_driven` |
| `uart` | `uart_overrun_ignored`, `uart_read_keeps_valid`, `uart_drop_not_flagged`, `uart_write_when_busy`, `uart_irq_mask_ignored`, `uart_status_ready_inverted`, `uart_tx_stop_low`, `uart_tx_start_high`, `uart_tx_short_frame`, `uart_rx_early_sample`, `uart_rx_late_sample`, `uart_rx_msb_first` |

## 4. Running

```bash
make formal                          # default engine (bitwuzla)
make formal FORMAL_ENGINE=yices      # another engine
```

`abc-bmc3` skips the induction proofs and the covers, which it does not do, and answers for the bounded proofs and the mutants.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
