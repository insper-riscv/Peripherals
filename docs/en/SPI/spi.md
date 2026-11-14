# Generic SPI master

🌐 [Português](../../pt-br/SPI/spi.md) · [English](../../en/SPI/spi.md)

## 1. What it is

A one-word SPI master with the four modes (CPOL and CPHA), words of 1 to 32 bits, most or least significant bit first, a clock divider, and release of the data line for three-wire slaves. On top of it sits a bus peripheral with transmit and receive queues, one to 64 chip select lines (one active at a time) and an interrupt. The SD card, the ADC128S022, the LTC2308 and the ADXL345 reuse the same master.

| Block | Role |
| :--- | :--- |
| `spi_master` | Master of one word per start request, with no queues and no chip select; the chip controllers instantiate this block |
| `uart_fifo` | Synchronous queue, one instance for transmit (the word plus the listen bit) and one for receive |
| `spi` | Memory-mapped top with the MISO synchronizer, the registers, the chip select lines, the sticky flags and the interrupt |

## 2. One-word master (`spi_master`)

### 2.1. Modes

CPOL picks the idle level of SCLK and CPHA picks the phase. The leading edge is the one that leaves idle and the trailing edge is the one that returns to it.

| Mode | CPOL | CPHA | SCLK idle | MOSI changes on the edge | The slave samples on the edge | The master samples on the edge |
| ---: | ---: | ---: | :--- | :--- | :--- | :--- |
| 0 | 0 | 0 | low | trailing (falling) | leading (rising) | trailing (falling) |
| 1 | 0 | 1 | low | leading (rising) | trailing (falling) | trailing (falling) |
| 2 | 1 | 0 | high | trailing (rising) | leading (falling) | trailing (rising) |
| 3 | 1 | 1 | high | leading (falling) | trailing (rising) | trailing (rising) |

The first bit is already on MOSI before the first leading edge for both CPHA values. The master always samples MISO on the trailing edge, the latest instant of the bit before the slave changes it, so MISO must arrive synchronized to `i_clk` (the `spi` peripheral and each chip controller already pass it through two flip-flops).

### 2.2. Word, order and timing

A word starts with a half-period of idle, has $n$ full SCLK periods and ends on the last trailing edge, which returns SCLK to the idle level. With $d$ the divider, the SCLK period and the number of edges are

$$ T_{SCLK} = 2 \cdot (d + 1) \ \text{cycles of } i\_clk, \qquad N_{edges} = 2n $$

The mode, the width $n$ (from 1 to the `word_width` parameter; a request out of range becomes the nearest limit), the bit order and the divider are captured at the start request, and a start request during a word is ignored. The received word is right-aligned in `o_rx_data` from the `o_done` pulse until the next word. Outside a word SCLK follows `i_cpol` and MOSI stays high, so the mode should only change with the chip select released. With `i_tx_drive` at 0 the word only listens, `o_mosi_oe` falls during it and stays at 0 until the next word, for the shared data line of three-wire slaves.

| Parameter | Default | Meaning |
| :--- | ---: | :--- |
| `divider_width` | 16 | Divider width, in bits |
| `word_width` | 32 | Maximum word width, from 1 to 32 |

| Port | Direction | Role |
| :--- | :--- | :--- |
| `i_cpol`, `i_cpha` | input | SPI mode |
| `i_lsb_first` | input | At 1 the least significant bit goes first |
| `i_word_bits` | input | Bits of the word, 6 bits |
| `i_divider` | input | Half the SCLK period minus one, in cycles |
| `i_tx_drive` | input | At 0 the word only listens |
| `i_start`, `i_tx_data` | input | Start request and the word to send |
| `o_busy`, `o_done`, `o_rx_data` | output | Word in progress, end pulse and received word |
| `o_sclk`, `o_mosi`, `o_mosi_oe`, `i_miso` | output and input | SPI pins, with the MOSI driver enable |

The minimum divider is 1 with CPHA 0. With CPHA 1 the slave data only appears after the leading edge and crosses the two synchronizer flip-flops, so the smallest divider is 2 with an ideal slave, and the delay of the chip and of the board adds cycles. The SCLK frequency is

$$ f_{SCLK} = \frac{f_{clk}}{2 \cdot (d + 1)} $$

## 3. Bus peripheral (`spi`)

### 3.1. Parameters and ports

| Parameter | Default | Meaning |
| :--- | ---: | :--- |
| `clock_hz` | 50000000 | Module clock frequency, in hertz |
| `reset_sclk_hz` | 1000000 | SCLK frequency after reset, in hertz |
| `word_width` | 32 | Maximum word width, in bits |
| `cs_count` | 1 | Chip select lines, from 1 to 64 |
| `rx_fifo_depth` | 16 | Words in the receive queue (at most 255) |
| `tx_fifo_depth` | 16 | Words in the transmit queue (at most 255) |

The reset divider is $\lceil clock\_hz / (2 \cdot reset\_sclk\_hz) \rceil - 1$. The bus ports are `i_clk`, `i_rst` (synchronous, active high), `i_write`, `i_read`, `i_address` (3 bits, word address), `i_data_in`, `o_data_out` and `o_irq`, plus the pins `o_sclk`, `o_mosi`, `o_mosi_oe`, `i_miso` and `o_cs_n` (one line per select, active low). The block window takes 6 words.

### 3.2. Registers

| Word | Name | Access | Reset | Description |
| ---: | :--- | :--- | ---: | :--- |
| 0 | `TX_DATA` | W | n/a | Word queued for transmission; with the queue full it is dropped and sets `TX_DROPPED` |
| 1 | `RX_DATA` | R | 0 | Oldest received word, removed from the queue by the read; returns zero with the queue empty |
| 2 | `STATUS` | R/W1C | `0x6` | State and sticky flags |
| 3 | `CONTROL` | R/W | `0x800` | Chip select, interrupts, mode, order and width |
| 4 | `DIVIDER` | R/W | section 3.1 | Bits 15:0, clock divider; takes effect from the next word |
| 5 | `TX_LISTEN` | W | n/a | Like `TX_DATA`, but the master releases MOSI during the word |

`STATUS` bits. Writing 1 to a W1C bit clears it, and a new event in the same cycle wins over the clear.

| Bit | Name | Access | Meaning |
| ---: | :--- | :--- | :--- |
| 0 | `RX_VALID` | R | At least one word in the receive queue |
| 1 | `TX_READY` | R | The transmit queue has room |
| 2 | `TX_EMPTY` | R | The transmit queue is empty (the last word may still be in progress) |
| 3 | `BUSY` | R | A word is in progress, just ended, or the transmit queue is not empty |
| 4 | `RX_FULL` | R | The receive queue is full |
| 5 | `DONE` | W1C | A word ended with the transmit queue empty |
| 6 | `RX_OVERRUN` | W1C | A received word was dropped with the receive queue full |
| 7 | `TX_DROPPED` | W1C | A write was dropped with the transmit queue full |
| 15:8 | `RX_LEVEL` | R | Words in the receive queue |
| 23:16 | `TX_LEVEL` | R | Words in the transmit queue |

`CONTROL` bits.

| Bit | Name | Meaning |
| ---: | :--- | :--- |
| 0 | `CS_ASSERT` | At 1 the line picked by `CS_SELECT` goes low |
| 1 | `RX_IRQ_ENABLE` | Interrupt while the receive queue is not empty |
| 2 | `TX_EMPTY_IRQ_ENABLE` | Interrupt while the transmit queue is empty |
| 3 | `DONE_IRQ_ENABLE` | Interrupt while `DONE` is 1 |
| 4 | `ERROR_IRQ_ENABLE` | Interrupt while `RX_OVERRUN` or `TX_DROPPED` is 1 |
| 5 | `CPOL` | SCLK idle level |
| 6 | `CPHA` | Phase |
| 7 | `LSB_FIRST` | At 1 the least significant bit goes first |
| 13:8 | `WORD_BITS` | Bits of the word, from 1 to `word_width` (reset 8) |
| 21:16 | `CS_SELECT` | Index of the chip select line; an index with no line leaves all of them high |

The `o_irq` output is level-sensitive and is the logical OR of the four enabled causes. The queue causes stop when the condition goes away, and the others stop when the software clears the flag.

## 4. Use by software

Each word written to `TX_DATA` produces a word in `RX_DATA`, so the software reads one word for each one it sends. To only receive, send any value. Changing `CS_ASSERT`, `CPOL` or `DIVIDER` is only safe with `BUSY` at zero. To change slave, clear `CS_ASSERT`, program the mode and `CS_SELECT` of the new slave and set `CS_ASSERT` again.

The C example exchanges 12-bit words with a mode 3 slave on line 2, and reads bytes from a three-wire slave with `TX_LISTEN`.

```c
#include <stdint.h>

/* Base of the peripheral, defined by the platform. */
#define SPI_BASE ((volatile uint32_t *)0x40000000u)

enum { TX_DATA, RX_DATA, STATUS, CONTROL, DIVIDER, TX_LISTEN };
enum { RX_VALID = 1u << 0, BUSY = 1u << 3 };
enum {
    CS_ASSERT = 1u << 0,
    CPOL = 1u << 5,
    CPHA = 1u << 6,
    LSB_FIRST = 1u << 7,
};

#define WORD_BITS(n) ((uint32_t)(n) << 8)
#define CS_SELECT(i) ((uint32_t)(i) << 16)

/* Program mode 3, 12-bit words, most significant bit first. */
void spi_select_slave_2(void)
{
    while ((SPI_BASE[STATUS] & BUSY) != 0) {
    }
    SPI_BASE[CONTROL] = CPOL | CPHA | WORD_BITS(12) | CS_SELECT(2);
    SPI_BASE[DIVIDER] = 24; /* SCLK = clock / 50 */
    SPI_BASE[CONTROL] |= CS_ASSERT;
}

/* Wait for a received word and return it. */
static uint32_t spi_wait_rx(void)
{
    while ((SPI_BASE[STATUS] & RX_VALID) == 0) {
    }
    return SPI_BASE[RX_DATA];
}

/* Exchange one word and return the received word. */
uint32_t spi_xfer(uint32_t word)
{
    SPI_BASE[TX_DATA] = word;
    return spi_wait_rx();
}

/* Read count bytes from a three-wire slave after the command cmd. */
void spi_read_three_wire(uint8_t cmd, uint8_t *out, int count)
{
    SPI_BASE[CONTROL] = CPOL | CPHA | WORD_BITS(8) | CS_SELECT(2) | CS_ASSERT;
    (void)spi_xfer(cmd);
    for (int i = 0; i < count; i++) {
        SPI_BASE[TX_LISTEN] = 0;
        out[i] = (uint8_t)spi_wait_rx();
    }
    SPI_BASE[CONTROL] = 0;
}
```

## 5. Who uses the master

The master has no pins of its own, and each chip controller carries the pins of its board.

| Controller | Document | SPI mode | Word width |
| :--- | :--- | :--- | ---: |
| `sd_spi` | [sd_spi.md](../SD/sd_spi.md) | 0 | 8 |
| `adc128s022` | [adc128s022.md](../ADC/adc128s022.md) | 3 | 16 |
| `ltc2308` | [ltc2308.md](../ADC/ltc2308.md) | 0 | 12 |
| `adxl345` | [adxl345.md](../ADXL345/adxl345.md) | 3 | 8 |

## 6. Verification

The `spi_master` entity test connects the master to a simulated slave in the four modes, at widths of 1, 5, 8, 12, 16, 24 and 32 bits and in both orders, and checks what the slave sampled on MOSI, what the master received, the number of edges, the period for three dividers, the idle level, a start request during a word, the listen word, back-to-back words and the width clamp. The peripheral test covers the reset, the registers, the queues, the three chip select lines, two slaves in different modes, the listen word, the error flags and the interrupt causes. The formal proof of `spi_master` covers the four modes with words of up to 4 bits and both orders, bit by bit on MOSI and on MISO, and is the same one `sd_spi` relies on in mode 0.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
