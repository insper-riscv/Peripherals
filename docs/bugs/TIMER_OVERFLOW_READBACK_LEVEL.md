# TIMER: the overflow register returned the instantaneous level

## Symptom

Reading the TIMER's overflow register (address 5, "overflow status, read to
clear") returned the instantaneous comparison `counter >= TOP`, not the status
that the overflow event had latched. In wrap mode that comparison is true for a
single cycle (the counter is cleared on the next edge), so software polling the
register almost never saw 1 even though the interrupt status had been set.

## Cause

The latched status exists and drives the interrupt line:

```vhdl
U_IRQ_STATUS_REG : entity WORK.FlipFlop     -- set by overflow_pulse, cleared by the read
   ...  destination => overflow_status
```

but the readback concatenated the raw level:

```vhdl
overflow_readback <= (31 downto 1 => '0') & overflow;  -- "Concatenate the overflow status"
```

where `overflow` is the output of `COUNTER_OVERFLOW` (`counter >= TOP`). The
comment, the decoder's name for the register (`ADDR_OVF_STATUS`, "Read-to-clear
overflow status") and the clear-on-read wiring all describe the latched status.

## Fix

`TIMER/TIMER.vhd`:

```vhdl
overflow_readback <= (31 downto 1 => '0') & overflow_status;
```

Together with the fix of [READ_TO_CLEAR_RACE.md](READ_TO_CLEAR_RACE.md), a read
returns the pending overflow and clears it.

## Tests

- `TIMER.timer.test_overflow_is_a_sticky_status_cleared_by_reading_it`: in
  saturate mode the counter reaches `TOP` and stays; several cycles later the
  register still reads 1, and a second read returns 0 (the overflow event
  happened once).

Reverting only this fix makes that test fail.
