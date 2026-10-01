# GPIO: the read map was shifted by one register

## Symptom

Reading the GPIO's interrupt registers returned the wrong register:

| Address read | Should return | Returned |
| :--- | :--- | :--- |
| 5 (`IRQ_MASK`) | interrupt mask | rising-edge mask |
| 6 (`RISE_MASK`) | rising-edge mask | falling-edge mask |
| 7 (`FALL_MASK`) | falling-edge mask | interrupt status |
| 8 (`IRQ_STAT`) | interrupt status | interrupt mask |

So the status could not be read at its own address: software polling address 8
for a pending interrupt got the mask it had just configured. Direction (0),
output (1 to 4) and pins (9) were not affected.

## Cause

`GPIO_OPERATION_DECODER` decides which register a read selects (`rd_sel`):

```vhdl
"000" when ADDR_DIR,
"001" when ADDR_OUT_LOAD / ADDR_OUT_SET / ADDR_OUT_CLR / ADDR_OUT_TGL,
"010" when ADDR_PINS,
"011" when ADDR_IRQ_STAT,
"100" when ADDR_IRQ_MASK,
"101" when ADDR_RISE_MASK,
"110" when ADDR_FALL_MASK,
```

`GPIO` feeds those selector values to a `GENERIC_MUX_8X1`, whose `source_N` is
chosen by `rd_sel = N - 1`. The sources were wired in this order:

```vhdl
source_4 => irq_mask,        -- selected by 011, but 011 is IRQ_STAT
source_5 => irq_rise_mask,   -- selected by 100, but 100 is IRQ_MASK
source_6 => irq_fall_mask,   -- selected by 101, but 101 is RISE_MASK
source_7 => irq_status,      -- selected by 110, but 110 is FALL_MASK
```

The decoder lists the status before the masks; the mux listed the masks before
the status. The decoder's table, its comments, and the register order of the
documentation all agree with each other, so the mux wiring is the side that was
wrong.

## Fix

`GPIO/GPIO.vhd`: the mux sources follow the decoder.

```vhdl
source_4 => irq_status,
source_5 => irq_mask,
source_6 => irq_rise_mask,
source_7 => irq_fall_mask,
```

## Tests

- `GPIO.gpio.test_registers_read_back_what_was_written`: writes distinct values
  to direction, output and the three masks, and reads each back at its own
  address.
- `GPIO.gpio.test_rising_edge_interrupt_is_read_and_cleared_by_reading_the_status`,
  `test_falling_edge_interrupt`, `test_an_edge_that_is_not_enabled_raises_nothing`:
  read the pending pin at address 8.
- `GPIO.gpio_operation_decoder.test_read_select`: pins the decoder side of the
  contract (address to `rd_sel`), so a change to either side breaks a test.

Reverting only this fix makes the four GPIO tests above fail.
