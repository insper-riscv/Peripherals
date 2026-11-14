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
| `clint` | `clint_props.sv` | induction, `tick_cycles` 3 | `MTIP` is the unsigned 64-bit comparison of the previous cycle, `MSIP` is bit 0 of `msip`, `mtime` adds one every three cycles and the read of every address (unmapped ones too) returns the register of the model; in the port write (low with `0xFFFFFFFF`, high, low) `MTIP` holds only if `mtime` already reached the old or the final `mtimecmp` |
| `plic_gateway` | `plic_gateway_props.sv` | bounded, 16 cycles | Pending follows the ideal gateway: one request per service, the claim clears it, only the complete unmasks the source, and pending does not fall with the line |
| `plic_arbiter` | `plic_arbiter_props.sv` | induction, 6 sources, 3 bits | `o_id` is the pending enabled source of highest priority strictly above the threshold, the lowest id on a tie, and zero with `o_valid` low without a candidate |
| `plic` | `plic_props.sv` | bounded, 14 cycles, 4 sources, 2 bits | `o_meip` is high exactly when a candidate exists; the claim returns the candidate of highest priority with a tie-break by id, or zero; the complete unmasks only the source written and enabled; a request is born on a free source with its line at 1; the read of every address and the visible state follow the model |
| `gpio_cell` | `gpio_cell_props.sv` | bounded, 16 cycles | Direction, output and masks change only by a write (set, clear and toggle with the bit mask); the pin read is the pin from two cycles ago; in level mode the status rises on a high level (rise mask) or a low level (fall mask); the status rises on the edge the masks select and falls only by a read or a reset; with the output on and steady the read and the output do not diverge |
| `uart_fifo` | `uart_fifo_props.sv` | bounded, 14 cycles, 3 words | Level, full and empty flags and acceptances follow a reference queue that shifts the words; a push on a full queue is accepted only with an accepted pop; the oldest word is the first one in that has not left, or zero when the queue is empty |
| `jtag_uart` | `jtag_uart_props.sv` | bounded, 14 cycles, 4-byte queues | With the host side idle, `CONTROL` stores and returns its three bits, and the interrupt is the OR of an enabled transmit-empty and an enabled error, the error cleared by reading `STATUS` |
| `uart` | `uart_props.sv` | induction and bounded, 200 cycles | Queue levels, overrun and dropped flags, mask, the three interrupt causes (receive, transmitter empty and error) and read of each address against the contract, from any state; the byte of the transmit queue reaches the PHY only when it is free; transmit frame with start, eight data bits from the least significant and stop, 16 cycles per bit; receive of a frame with noise at the edges of each data bit, sampled mid-bit |
| `console` | `console_props.sv` and `tests/vhdl/console_equiv.vhd` | bounded, 200 cycles (`pinos`) and 30 cycles (`jtag`) | Miter of the console against the block it chooses (`uart` or `jtag_uart`) on the same free inputs: data read, interrupt, transmit line and JTAG chain output are equal at every cycle, also with TX and RX inverted (the reference writes the inversion apart) |
| `audio_xck_gen` | `audio_xck_gen_props.sv` | bounded, 20 cycles, step and modulus up to 9 | The accumulator stays below the modulus and, after $k$ updates, the master clock has flipped exactly $\lfloor k \cdot step / modulus \rfloor$ times, with none lost or doubled and the level equal to the parity of the count |
| `audio_frame_clocks` | `audio_frame_clocks_props.sv` | bounded, 24 cycles, dividers up to 3 and 2 | The BCLK flips every divider master flips, the LRCK every cycles-per-channel BCLK falls, and both stay at zero with generation disabled |
| `audio` | `audio_props.sv` | bounded, 20 cycles, 3-word queues, slave mode | `CONTROL`, `IRQ_LEVEL`, `LEVELS`, `CONFIG` and `CAPS` read back the contract, the queue levels follow accepted pushes and pops, `TX_DATA` is only refused with a full queue and no pop, the three `STATUS` flags follow their events with clear-by-one, the interrupt is the OR of the three terms with their enables, the master clock stops without `CLK_EN` and the bit and channel pins are not driven |
| `flash_controller` | `flash_controller_props.sv` | bounded, 14 cycles, 4-word page | The command pulse comes only from a write to register 0, with the three low bits of the data and the stored address; the read of each address returns the command address, the chip state, the buffer index or the interrupt registers, and zero in the other addresses and without a read; the chip finishing and refusing become status bits that only a write of one clears, and `o_irq` is the OR of status and enable; the buffer index advances at each data write and is set by a write to register 3; the chip reads from the buffer, one edge later, the word the write left at the index |
| `video_timing` (HDMI) | `hdmi_timing_props.sv` | induction, and bounded 280 cycles for the measures, 15 x 11 mode | HS, VS, visible area, image rectangle, framebuffer coordinates and the registered frame outputs follow column and line counters defined by the generics alone, in both polarities; measures on the outputs alone give the distance between HS pulses (line), VS pulses (frame), the pulse widths, the DE width and the lines with DE per frame |
| `hdmi_regs` | `hdmi_regs_props.sv` | induction, 11-bit address | The mask changes only by write; the pending bits add the end-of-frame and pin-activation edges, are cleared by writing 1 and an event in the same cycle wins over the clear; `o_irq` is the OR of the enabled pending bits; the restart pulse comes only from writing bit 0 of word 12 with the sequencer present; each word from 8 to 14 reads the contract and the others read zero |
| `hdmi_init_seq` | `hdmi_init_seq_props.sv` | bounded, 40 cycles, 3 entries | The table goes out in order, one pending write at a time, with the register and value of the current entry; state, done and counters follow the ideal list; the start counts only with the sequence stopped |
| `hdmi_i2c_writer` | `hdmi_i2c_writer_props.sv` | bounded, 250 cycles, quarter bit of 2 cycles | Open drain only (values always zero), free bus when stopped, SDA changes with SCL high only at start and stop, SDA released in the three acknowledge pulses, 27 data pulses plus the stop pulse and a one-cycle done |
| `hdmi_audio` | `hdmi_audio_props.sv` | bounded, 520 cycles (ratio 128) and 1030 cycles (ratio 256), system clock at twice the MCLK | Between two LRCLK flips, measured on the outputs alone, the MCLK rises `ratio / 2` times, the SCLK rises 32 times and `ratio` cycles pass; between two SCLK rises the MCLK rises `ratio / 64` times; the serial data changes only in the cycle after an SCLK fall; the first LRCLK flip goes from the left channel to the right one and two flips happen in time |

Each entity has a cover that shows the proved situation is reachable.

## 2. How each proof is built

1. The netlist of the `timer`, the `uart` and the `clint` has the internal registers exposed as `dbg_*` outputs, which lets the induction state the invariants without changing the logic. In `clint` they are `msip`, the two halves of `mtimecmp` and of `mtime` and the phase of the divider. The 64-bit counter of the `clint` is the `counter64` of Common-Components, which has its own proof there; here it is exercised by the proof of the `clint`, and the `mtime_*` mutants are applied at this instance point. The invariant says the ideal model is that state (the ideal `mtime` is the high half plus the pending carry), and the registered MTIP of the model is the comparison of the `mtime` and the `mtimecmp` of the previous cycle.
2. In the `gpio_cell` the bidirectional pin of the netlist becomes an input and an output, and the environment drives the pin only when the direction is input.
3. In the `uart` the baud generator runs with `baud_freq = 0` and `baud_limit = 0`, which makes `ce16` hold on every cycle and a bit last 16 cycles. The real ratios only change how long `ce16` takes to arrive, not the frame format nor the sampling point in `ce16` cycles. The queues have 3 words in the proof, the smallest value whose pointers wrap outside a power of two, which brings filling within reach of the induction and the covers.
4. In the port write sequence (`-DSEQ`) the induction uses one more invariant per step: after the low half with `0xFFFFFFFF` the `mtimecmp` is the old high half with the low half at `0xFFFFFFFF`, after the high half it is the final high half with the low half at `0xFFFFFFFF`, and after the final low half it is the final value; the `mtimecmp` the previous cycle compared is the current one or that of the previous step, and `mtime` never decreases. The argument that MTIP never rises too early is then: `mtime` is monotonic and every intermediate `mtimecmp` is greater than or equal to the old value or to the final one. Monotony assumes that `mtime` does not wrap around in $2^{64}$ ticks (more than five thousand years at 100 MHz), which the proof states as the state `0xFFFFFFFFFFFFFFFF` being excluded.
5. The `clock_prescaler` uses 3 bits and any constant prescaler; the `timer` uses the prescaler `tick` as an input of the model, because the tick period is the property of the `clock_prescaler`. Together the two proofs fix the pace of the overflow: the counter advances one per tick and the tick comes every $P + 1$ cycles.

## 3. Mutants

Each deliberate defect of the VHDL must make a proof fail. `formal/run.sh` applies each edit with `sed` to a copy of the file and requires the `fail` verdict.

| Entity | Mutants |
| :--- | :--- |
| `alu_ge_unsigned` | `alu_strict`, `alu_no_invert` |
| `counter_overflow` | `ovf_swapped`, `ovf_strict` |
| `clock_prescaler` | `presc_unregistered`, `presc_strict`, `presc_no_clear` |
| `timer` | `timer_top_enable`, `timer_prescaler_enable`, `timer_top_reset`, `timer_mode_inverted`, `timer_start_ignored`, `timer_mask_ignored`, `timer_status_not_cleared`, `timer_level_not_edge`, `timer_pwm_inverted`, `timer_read_select`, `timer_write_address` |
| `clint` | `clint_msip_bit`, `clint_cmp_reset_zero`, `clint_cmp_hi_address`, `clint_mtip_unregistered`, `clint_read_swapped`, `clint_tick_early`, `clint_mtime_hi_address`, `clint_strict_compare`, `clint_seq_cmp_clear_not_ones`, `mtime_carry_lost`, `mtime_hi_incoherent`, `mtime_write_loses` |
| `plic_gateway` | `plicgw_no_mask`, `plicgw_claim_ignored`, `plicgw_complete_ignored`, `plicgw_reset_ignored` |
| `plic_arbiter` | `plicarb_tie_highest`, `plicarb_threshold_not_strict`, `plicarb_enable_ignored`, `plicarb_pending_ignored`, `plicarb_threshold_ignored`, `plicarb_last_wins` |
| `plic` | `plic_claim_not_clearing`, `plic_complete_any_id`, `plic_complete_ignores_enable`, `plic_complete_any_address`, `plic_claim_any_address`, `plic_priority_address`, `plic_pending_reads_enable`, `plic_meip_constant`, `plic_threshold_shifted`, `plic_claim_reads_zero`, `plic_enable_not_reset`, `plic_enable_bit_shifted`, `plic_claim_address` |
| `gpio_cell` | `cell_dir_always`, `cell_no_set_clear`, `cell_toggle_is_load`, `cell_mask_ignored`, `cell_fall_uses_rise`, `cell_status_not_cleared`, `cell_level_ignored`, `cell_level_fall_is_high`, `cell_level_mode_write`, `cell_pin_not_driven` |
| `uart_fifo` | `fifo_no_wrap`, `fifo_overwrite_when_full`, `fifo_no_reuse_on_pop`, `fifo_pop_not_counted`, `fifo_push_not_counted`, `fifo_pop_keeps_head`, `fifo_empty_shows_data`, `fifo_pop_when_empty` |
| `audio_xck_gen` | `xckg_wrap_late`, `xckg_no_discount`, `xckg_no_toggle` |
| `audio_frame_clocks` | `fclk_div_short`, `fclk_lrck_on_rise`, `fclk_slot_short` |
| `audio` | `audio_tx_irq_strict`, `audio_rx_irq_mask_ignored`, `audio_drop_flag_always`, `audio_thresholds_swapped`, `audio_status_full_inverted`, `audio_w1c_wrong_bit`, `audio_word_bits_lost`, `audio_clock_not_gated` |
| `flash_controller` | `flashc_ptr_stuck`, `flashc_cmd_any_write`, `flashc_status_swapped`, `flashc_addr_any_write`, `flashc_op_shifted`, `flashc_word_misplaced`, `flashc_read_ungated`, `flashc_ptr_write_ignored`, `flashc_done_on_busy_rising`, `flashc_refused_level`, `flashc_irq_mask_ignored`, `flashc_w1c_clears_all`, `flashc_event_loses_to_clear`, `flashc_status_bit_lost` |
| `video_timing` (HDMI) | `hdmitim_hs_late`, `hdmitim_vs_wide`, `hdmitim_line_short`, `hdmitim_vs_polarity`, `hdmitim_visible_wide`, `hdmitim_vblank_late`, `hdmitim_image_not_centered`, `hdmitim_vsync_stuck` |
| `hdmi_regs` | `hdmiregs_event_loses_to_clear`, `hdmiregs_mask_ignored`, `hdmiregs_start_without_sequencer`, `hdmiregs_start_wrong_bit`, `hdmiregs_mask_shifted`, `hdmiregs_frame_level`, `hdmiregs_pin_level`, `hdmiregs_clear_wrong_bit`, `hdmiregs_status_swapped`, `hdmiregs_mask_not_reset`, `hdmiregs_count_swapped` |
| `hdmi_init_seq` | `hdmiseq_nack_ignored`, `hdmiseq_index_stuck`, `hdmiseq_done_early`, `hdmiseq_done_never`, `hdmiseq_sent_not_counted`, `hdmiseq_reissues`, `hdmiseq_auto_ignored`, `hdmiseq_register_swapped`, `hdmiseq_audio_overwrites`, `hdmiseq_audio_dropped` |
| `hdmi_i2c_writer` | `hdmii2c_ack_driven`, `hdmii2c_two_bytes`, `hdmii2c_out_high`, `hdmii2c_busy_short` |
| `hdmi_audio` | `hdmiaud_slot_short`, `hdmiaud_mclk_half`, `hdmiaud_clocks_swapped`, `hdmiaud_ratio_ignored` |
| `jtag_uart` | `jtagu_tx_empty_inverted`, `jtagu_error_mask_ignored`, `jtagu_control_bit_swapped`, `jtagu_lost_stays` |
| `uart` | `uart_overrun_ignored`, `uart_drop_not_flagged`, `uart_w1c_wrong_bit`, `uart_tx_pops_when_busy`, `uart_rx_pops_on_any_read`, `uart_irq_mask_ignored`, `uart_irq_tx_empty_inverted`, `uart_irq_error_ignores_drop`, `uart_irq_error_mask_ignored`, `uart_control_bit_swapped`, `uart_status_ready_inverted`, `uart_idle_ignores_phy`, `uart_levels_swapped`, `uart_tx_stop_low`, `uart_tx_start_high`, `uart_tx_short_frame`, `uart_rx_early_sample`, `uart_rx_late_sample`, `uart_rx_msb_first` |
| `console` | `console_tx_polarity`, `console_rx_polarity`, `console_address_bits`, `console_read_strobe`, `console_jtag_write_strobe` |

## 4. Running

```bash
make formal                          # default engine (bitwuzla)
make formal FORMAL_ENGINE=yices      # another engine
```

`abc-bmc3` skips the induction proofs and the covers, which it does not do, and answers for the bounded proofs and the mutants.

`yices` skips four bounded proofs of the console, of 200 cycles over the whole UART, which it does not close within `FORMAL_TIMEOUT` (900 s by default): the pins backend, the inverted pins backend and the mutants `console_rx_polarity` and `console_read_strobe`. `bitwuzla`, `boolector` and `abc-bmc3` answer all four, and the aggregator `formal/aggregate.sh` still demands a verdict from at least one engine for each proof, so the `yices` skip hides none of them.

## 5. Warnings are errors

A warning from GHDL, Yosys or SymbiYosys flags code that is out of the norm or at its limit, and the cause is fixed in the code or in the proof. No option hides a warning (`formal/run.sh` has no `-Wno-*`).

1. After each `ghdl -a` and `ghdl --synth`, `formal/run.sh` scans the output of GHDL. After each `sby`, it scans every log of the proof. This holds for the proofs and for the mutants.
2. The `scan_warnings` function matches the word `warning` or its plural, in any case, as a whole word. It catches `file.vhd:12:5:warning: ...` from GHDL and `Warning: ...` from Yosys and SymbiYosys. It does not catch names with an underscore (`warning_count`), because the underscore is part of the word, and it skips the Yosys summary with a count of zero (`Warnings: 0 unique messages, 0 total`).
3. Each line found goes to `build/formal/warnings.txt` and to the standard error as `file:line:text`. At the end of the run, a non-empty `warnings.txt` fails `formal/run.sh`.
4. There is one exact exception, only for the `abc-bmc3` engine: the messages ABC itself prints when it reads the AIGER file SymbiYosys hands it, `The last N outputs are interpreted as constraints` (the assumptions and the clock of the `clk2ff` step) and `The network has no constraints`. They describe the file format of the tool, not the design, and live in the `abc_notes` variable. The messages `Treating undriven bit props.\clk like $anyseq` and `Treating a total of N undriven bits` are not accepted: the script of the engine flattens the design and purges the aliases of the clock before the AIGER file is written. Yices, bitwuzla and boolector have no exception, and any other message, in any engine, is an error.

The warnings that the netlist of each proof had and how each cause was handled:

| Warning | Origin | Handling |
| :--- | :--- | :--- |
| `comparing non-numeric vector is unexpected` | `baudGen.vhd` (OpenCores), comparison of `std_logic_vector` | The comparison is made between `unsigned` values, with the same behavior and the change recorded in the header and in `ORIGIN.md` |
| `unhandled attribute "ramstyle"` and `"altera_attribute"` | Quartus synthesis hints in `uart_fifo.vhd` and `synchronizer.vhd` | GHDL does not know these attributes, which do not change the proved logic. The netlist is synthesized from a copy without these two hints, with the lines in the same place. Any other unknown attribute is still an error |
| `Wire ... is used but has no driver` | Read multiplexer of the 3-word queue after `memory_map` (abc-bmc3 included), whose fourth address is never reached | The branch without a driver gets zero (`setundef -undriven -zero`) |
| `Yosys has only limited support for tri-state logic` | Tri-state PWM output of the `timer` | The high-impedance state becomes zero in the netlist, as for the pin of the `gpio_cell`. The properties look at the internal PWM register, not at the pin |
| `Identifier ... is implicitly declared` and `Wire ... is used but has no driver` | Mutants that leave an exposed signal without a reader (`timer_level_not_edge`, `uart_levels_swapped`), which GHDL does not write in the netlist | The `dbg_` output of a signal that is not in the netlist is the constant zero, and the mutant is still caught by the properties of the signals it changes |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
