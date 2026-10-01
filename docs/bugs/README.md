# Bugs found in the peripherals

The GPIO and the TIMER came from `insper-riscv/RV32` (`src/GPIO`, `src/TIMER`).
Until the move to this repository they had only been compiled by Quartus: no
testbench existed and no working SoC top instantiated them (the only top that
did, the deprecated `L2IP`, does not build against the current core). Simulating
them with GHDL for the first time, and writing the first entity tests, turned up
the bugs below. Each document has the symptom, the cause in the code, the fix, and
the tests that catch it.

| Document | Where | Effect |
| :--- | :--- | :--- |
| [GPIO_READ_MAP_SHIFTED.md](GPIO_READ_MAP_SHIFTED.md) | `GPIO/GPIO.vhd` | reading the interrupt status, mask, rising mask or falling mask returned the register after it |
| [READ_TO_CLEAR_RACE.md](READ_TO_CLEAR_RACE.md) | `GPIO/GPIO_CELL.vhd`, `TIMER/TIMER.vhd` | a status that clears on read vanished while being read |
| [TIMER_OVERFLOW_READBACK_LEVEL.md](TIMER_OVERFLOW_READBACK_LEVEL.md) | `TIMER/TIMER.vhd` | the overflow register returned the instantaneous level, not the latched status |

All three fixes are in one commit (`a206414`, "Fix the read-to-clear statuses and
the GPIO read map; add the entity tests"), apart from the GHDL compatibility
change, so they are easy to review or revert. No code in this project used the
affected registers: the only software that touched a GPIO
(`L2IP/sw/src/gpio.c`) wrote the direction, set and clear registers and read the
pins, none of the affected ones.

## Not a bug, but found on the same day: GHDL and port-map actuals

The sources used expressions of signals as port-map actuals, for example
`enable => wr_signals(1) OR (wr_signals(2) AND data_in)` or
`source_1 => (0 => data_in)`. Quartus accepts that; GHDL (VHDL-93 and 2008 mode)
requires a name or a globally static expression there and stops with
`actual expression must be globally static`. `GPIO_CELL`, `TIMER` and
`CLOCK_PRESCALER` now compute those expressions on intermediate signals and map
the signals; the logic is unchanged (commit `56f524b`).

## How the fixes were verified

With the fixes, all 31 tests pass. Reverting one fix at a time makes exactly
these fail:

| Fix reverted | Tests that fail |
| :--- | :--- |
| GPIO read map | `GPIO.gpio`: `test_registers_read_back_what_was_written`, `test_rising_edge_interrupt_is_read_and_cleared_by_reading_the_status`, `test_falling_edge_interrupt`, `test_an_edge_that_is_not_enabled_raises_nothing` |
| Read-to-clear race | `GPIO.gpio`: `test_rising_edge_interrupt_is_read_and_cleared_by_reading_the_status`, `test_falling_edge_interrupt`, `test_masked_pin_raises_nothing`; `TIMER.timer`: `test_overflow_is_a_sticky_status_cleared_by_reading_it` |
| TIMER overflow readback | `TIMER.timer`: `test_overflow_is_a_sticky_status_cleared_by_reading_it` |

(The two interrupt tests of the GPIO fail for either of the first two bugs: the
status is unreachable at the wrong address, and it is gone at the right one.)
