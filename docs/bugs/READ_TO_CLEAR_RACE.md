# GPIO and TIMER: a status that clears on read vanished while being read

## Symptom

Two registers are documented as read-to-clear: the GPIO interrupt status
(address 8) and the TIMER overflow status (address 5). Reading them returned 0
even when the event had happened, and the interrupt line dropped as soon as the
read began. Software could never see the pending bit it was supposed to
acknowledge.

## Cause

The decoders raise a clear strobe while the read is in progress:

```vhdl
-- GPIO_OPERATION_DECODER
wr_en(IRQ_CLR_I) <= read when address = ADDR_IRQ_STAT else '0';
-- TIMER_OPERATION_DECODER
wr_en(WR_OVF_CLR_I) <= read when address = ADDR_OVF_STATUS else '0';
```

and the status flip-flop used `FlipFlop`, whose clear is **asynchronous**:

```vhdl
process(clock, clear)
begin
  if clear = '1' then
    destination <= '0';
  elsif rising_edge(clock) then ...
```

With `read` asserted, the clear acted immediately, so `data_out`, a combinational
multiplexer over the register, showed 0 for the whole cycle of the read. A bus
master samples `data_out` at the clock edge at the end of that cycle: it always
saw the already-cleared value.

## Fix

The status flip-flops use `GENERIC_FLIP_FLOP`, whose clear is **synchronous**
(the one the two directories already carried, unused), so the read returns the
status during the cycle and the clock edge that ends the read clears it:

```vhdl
-- GPIO/GPIO_CELL.vhd
U_IRQ_STATUS : entity WORK.GENERIC_FLIP_FLOP
-- TIMER/TIMER.vhd
U_IRQ_STATUS_REG : entity WORK.GENERIC_FLIP_FLOP
```

`GENERIC_FLIP_FLOP` lives in `common/`. Two consequences, both acceptable: the
global `clear` of these two flip-flops is now also synchronous (a reset needs a
clock edge, and the testbenches hold it for three), and an event that arrives on
the very edge a read clears the status is lost (the clear wins over the set).

## Tests

- `GPIO.gpio.test_rising_edge_interrupt_is_read_and_cleared_by_reading_the_status`
  and `test_falling_edge_interrupt`: the read returns the pending pin, the
  interrupt line is low afterwards, and a second read returns 0.
- `GPIO.gpio.test_masked_pin_raises_nothing`: the status read returns only the
  unmasked pin.
- `TIMER.timer.test_overflow_is_a_sticky_status_cleared_by_reading_it` and
  `test_interrupt_needs_the_mask_and_is_cleared_by_reading_the_status`: the read
  returns 1, clears it, and drops the interrupt.

Reverting only this fix makes the first three and the sticky-status TIMER test fail.
