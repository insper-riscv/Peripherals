# 16x2 LCD Controller

🌐 [Português](../../pt-br/LCD/lcd.md) · [English](../../en/LCD/lcd.md)

## 1. What it is

A bus peripheral that drives the 16x2 alphanumeric LCD module of the DE2-115, compatible with the HD44780 controller, through the 8-bit parallel interface (section 4.6 of the board manual). Software writes commands and data to registers, a write queue absorbs the burst, and a physical layer generates the bus timing and waits for the chip to finish each operation. The chip initialization can be done in hardware, by a generic.

| Block | Function |
| :--- | :--- |
| `lcd_regs` | Bus decoding, registers, error flags and interrupt |
| `uart_fifo` | 9-bit write queue (RS and byte), the same one the UART uses |
| `lcd_phy` | Timing of RS, RW, EN and data, wait for the busy flag or for a fixed delay |
| `lcd_init` | Optional initialization sequence |
| `lcd` | Structural top that connects the blocks and the busy-flag synchronizer |

## 2. Pins

| Port | Direction | Board pin | Description |
| :--- | :--- | :--- | :--- |
| `i_lcd_data` | input | `LCD_DATA[7:0]` | Value of the data pins; only bit 7 is read (busy flag) |
| `o_lcd_data` | output | `LCD_DATA[7:0]` | Value driven on the data pins |
| `o_lcd_data_oe` | output | `LCD_DATA[7:0]` | Driver enable, for the tristate layer of the board top |
| `o_lcd_rs` | output | `LCD_RS` | 0 command, 1 data |
| `o_lcd_rw` | output | `LCD_RW` | 0 write, 1 read; fixed at 0 without `has_rw` |
| `o_lcd_en` | output | `LCD_EN` | Chip enable |
| `o_lcd_on` | output | `LCD_ON` | Module power, set by `CONTROL` |
| `o_lcd_blon` | output | `LCD_BLON` | Backlight, set by `CONTROL`; the current DE2-115 modules have no backlight |

The peripheral instantiates no vendor buffer. The board top connects `o_lcd_data` to the pins when `o_lcd_data_oe` is 1 and brings the pin value to `i_lcd_data`. The driver is on only during a write, with RW low, and the chip drives the bus only with RW and EN high.

## 3. Registers

The address is a word address of 3 bits and the block takes 8 words. Addresses 6 and 7 read zero and ignore writes.

| Word | Name | Access | Reset | Description |
| ---: | :--- | :--- | :--- | :--- |
| 0 | `COMMAND` | W | n/a | Bits 7:0 enter the queue with RS = 0; a read returns zero |
| 1 | `DATA` | W | n/a | Bits 7:0 enter the queue with RS = 1; a read returns zero |
| 2 | `STATUS` | R/W1C | `0x4` | Flags in the table below; writing 1 to `DROPPED` or `TIMEOUT` clears it |
| 3 | `CONTROL` | R/W | `0x6` with `has_rw`, `0x4` without | Bits in the table below |
| 4 | `DELAY` | R/W | 50 µs in cycles | Bits 23:0, wait cycles after an ordinary command or a data byte |
| 5 | `DELAY_LONG` | R/W | 2 ms in cycles | Bits 23:0, wait cycles after clear (`0x01`) or return home (`0x02`, `0x03`) |

`STATUS`.

| Bit | Name | Meaning |
| ---: | :--- | :--- |
| 0 | `BUSY` | Initialization, a non-empty queue or a bus operation is in progress |
| 1 | `FIFO_FULL` | The queue is full |
| 2 | `FIFO_EMPTY` | The queue is empty |
| 3 | `INIT_BUSY` | The hardware initialization is in progress |
| 4 | `DROPPED` | A write was dropped because the queue was full; stays set until 1 is written |
| 5 | `TIMEOUT` | The busy flag did not fall within the time limit; stays set until 1 is written |
| 15:8 | `FIFO_LEVEL` | Number of words in the queue |

`CONTROL`.

| Bit | Name | Meaning |
| ---: | :--- | :--- |
| 0 | `EMPTY_IRQ_ENABLE` | Enables the queue-empty interrupt |
| 1 | `POLL_ENABLE` | Wait for the busy flag instead of using `DELAY`; only exists with `has_rw`, and without it the bit reads 0 and ignores writes |
| 2 | `LCD_ON` | Level of the `LCD_ON` pin |
| 3 | `BACKLIGHT_ON` | Level of the `LCD_BLON` pin |

The `o_irq` output is level-triggered and is 1 with an empty queue, the enable on and the initialization finished. It falls when a word is written and returns when the physical layer takes the last one out of the queue. A bus access completes in one cycle and a read has no side effect (the `i_read` port exists only for uniformity with the other peripherals).

## 4. Timing

### 4.1. Write

Each operation runs the phases below, with durations given by generics in nanoseconds and converted to cycles of the `clk_freq_hz` clock, rounded up with a minimum of one cycle.

| Phase | Generic | Default | Chip minimum |
| :--- | :--- | ---: | ---: |
| RS, RW and data before EN | `setup_ns` | 100 ns | 40 ns (data 80 ns) |
| EN high | `pulse_ns` | 300 ns | 230 ns |
| RS, RW and data after EN | `hold_ns` | 100 ns | 10 ns |

The three defaults add up to the 500 ns minimum EN cycle. The chip captures the data on the falling edge of EN.

### 4.2. Waiting for the operation to end

After the write the chip is busy. The physical layer waits in one of two ways.

| Mode | When | How |
| :--- | :--- | :--- |
| Busy flag | `has_rw` and `POLL_ENABLE` on | Repeats reads with RW = 1 and RS = 0 and samples data bit 7 in the last cycle of the EN pulse, until it is 0 or the `busy_timeout_us` time runs out (then `TIMEOUT` lights and the layer moves on) |
| Fixed delay | Without `has_rw`, or with `POLL_ENABLE` off | Waits `DELAY` cycles after ordinary commands and data, and `DELAY_LONG` cycles after clear and return home |

Bit 7 goes through a two-stage synchronizer. The EN pulse must last longer than the chip data delay (160 ns) plus the two synchronizer cycles; the 300 ns default covers this from 50 MHz, and for slower clocks raise `pulse_ns`.

### 4.3. Hardware initialization

With `auto_init` on, after reset the peripheral waits `power_up_us` and sends the commands of the table, with fixed delays and without reading the busy flag. Software writes during the sequence wait in the queue and go out after it; `INIT_BUSY` is 1 and the interrupt stays 0 until the end.

| Step | Byte | Wait after |
| ---: | :--- | :--- |
| 1 | `0x30` | 5 ms |
| 2 and 3 | `0x30` | 200 µs |
| 4 | `0x38` (8 bits, two lines, 5x8 font) | `exec_us` |
| 5 | `0x0C` (display on, cursor off) | `exec_us` |
| 6 | `0x01` (clear) | `exec_long_us` |
| 7 | `0x06` (entry mode: cursor to the right) | `exec_us` |

## 5. Parameters

| Generic | Default | Description |
| :--- | ---: | :--- |
| `data_width` | 32 | Bus width, at least 24 |
| `clk_freq_hz` | 50000000 | Clock frequency |
| `fifo_depth` | 16 | Queue depth, up to 255 |
| `has_rw` | true | The `LCD_RW` pin is connected to the peripheral |
| `auto_init` | false | Turns on the hardware initialization |
| `setup_ns`, `pulse_ns`, `hold_ns` | 100, 300, 100 | Bus timings |
| `power_up_us` | 20000 | Power-up wait before the initialization |
| `exec_us` | 50 | Reset value of `DELAY` and wait of the initialization |
| `exec_long_us` | 2000 | Reset value of `DELAY_LONG` and clear wait of the initialization |
| `busy_timeout_us` | 10000 | Time limit of the busy-flag wait |

The chip timings quoted in this document (40 ns, 230 ns, 10 ns, 160 ns, 500 ns cycle, 37 µs per command, 1.52 ms for clear, 15 ms power-up, 4.1 ms and 100 µs wake-up) come from what is known of the HD44780 and were not checked against the datasheet, which is not in `Docs`; the defaults leave margin over them.

## 6. Usage sequence

With `auto_init` off, software waits 20 ms after power-up and sends the sequence. In C, waiting on the busy state:

```c
#define LCD_COMMAND (*(volatile uint32_t *)(LCD_BASE + 0x00))
#define LCD_DATA    (*(volatile uint32_t *)(LCD_BASE + 0x04))
#define LCD_STATUS  (*(volatile uint32_t *)(LCD_BASE + 0x08))
#define LCD_FIFO_FULL (1u << 1)
#define LCD_BUSY      (1u << 0)

static void lcd_put(volatile uint32_t *reg, uint8_t byte)
{
    while (LCD_STATUS & LCD_FIFO_FULL) { }
    *reg = byte;
}

void lcd_print(const char *text)
{
    lcd_put(&LCD_COMMAND, 0x38);
    lcd_put(&LCD_COMMAND, 0x0C);
    lcd_put(&LCD_COMMAND, 0x01);
    lcd_put(&LCD_COMMAND, 0x06);
    while (*text) { lcd_put(&LCD_DATA, (uint8_t)*text++); }
    lcd_put(&LCD_COMMAND, 0xC0);   /* start of the second line */
    while (LCD_STATUS & LCD_BUSY) { }
}
```

With `auto_init` on, the loop of `lcd_print` starts directly at `LCD_DATA`, because the writes wait in the queue for the initialization.

## 7. Verification

The cocotb tests use a behavioral model of the HD44780 with a 128-position DDRAM, cursor, clear, entry mode and the busy flag. The model checks the bus timings, refuses a write while the chip is busy, requires 15 ms of power-up and requires no conflict on the data bus. The formal proofs cover the physical layer (conflict, setup, hold, pulse, operation length, time limit) and the registers (control, error flags, interrupt, read-back); the queue is the `uart_fifo`, proved with the UART.
