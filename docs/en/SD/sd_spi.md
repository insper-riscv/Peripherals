# SD card controller in SPI mode

🌐 [Português](../../pt-br/SD/sd_spi.md) · [English](../../en/SD/sd_spi.md)

## 1. What it is

Bus peripheral that drives an SD or micro SD card through SPI mode. The software queues bytes, the SPI master exchanges them with the card, and every transmitted byte returns one received byte, also queued. The peripheral has a chip select register, a clock divider set by a generic and by a register, and a level interrupt with four causes.

The peripheral is made of three blocks.

| Block | Function |
| :--- | :--- |
| `sd_spi_phy` | The generic SPI master (`spi_master`, see [spi.md](../SPI/spi.md)) fixed at mode 0 (SCLK idles low, MOSI changes on the falling edge and the card samples on the rising edge), with an 8-bit word, most significant bit first and the divider captured at the start of each byte |
| `uart_fifo` | Synchronous byte queue, one instance for transmit and one for receive |
| `sd_spi` | Top with the MISO synchronizer, the registers, the sticky flags and the interrupt |

## 2. Pins and boards

Neither manual lists the function of each pin in SPI mode; the mapping is the one of the SD card specification, where the command line becomes MOSI, data 0 becomes MISO and data 3 becomes the chip select. Both boards connect the socket to the FPGA at 3.3 V, with no card detect pin (the DE2-115 has only the write protect pin, `SD_WP_N`).

| Peripheral port | Direction | SPI function | DE0-CV pin | DE2-115 pin |
| :--- | :--- | :--- | :--- | :--- |
| `o_sd_sclk` | output | SCLK | `SD_CLK` (`PIN_H11`) | `SD_CLK` (`PIN_AE13`) |
| `o_sd_mosi` | output | MOSI | `SD_CMD` (`PIN_B11`) | `SD_CMD` (`PIN_AD14`) |
| `i_sd_miso` | input | MISO | `SD_DATA0` (`PIN_K9`) | `SD_DAT[0]` (`PIN_AE14`) |
| `o_sd_cs_n` | output | Chip select, active low | `SD_DATA3` (`PIN_C11`) | `SD_DAT[3]` (`PIN_AC14`) |
| none | n/a | Unused in SPI mode | `SD_DATA1` (`PIN_D12`), `SD_DATA2` (`PIN_E12`) | `SD_DAT[1]` (`PIN_AF13`), `SD_DAT[2]` (`PIN_AB14`), `SD_WP_N` (`PIN_AF14`) |

The unused lines stay as inputs in the platform top.

## 3. Generics and ports

| Generic | Default | Meaning |
| :--- | ---: | :--- |
| `clock_hz` | 50000000 | Module clock frequency, in hertz |
| `init_sclk_hz` | 400000 | SCLK frequency after reset; card initialization allows at most 400 kHz |
| `rx_fifo_depth` | 32 | Bytes in the receive queue (at most 255) |
| `tx_fifo_depth` | 32 | Bytes in the transmit queue (at most 255) |

The reset divider is

$$ \text{DIVIDER}_{reset} = \left\lceil \frac{\text{clock\_hz}}{2 \cdot \text{init\_sclk\_hz}} \right\rceil - 1 $$

and the SCLK frequency is

$$ f_{SCLK} = \frac{\text{clock\_hz}}{2 \cdot (\text{DIVIDER} + 1)} $$

The smallest accepted divider is 1, because the MISO line crosses two synchronizer flip-flops and is sampled on the falling edge of SCLK.

The bus ports are `i_clk`, `i_rst` (synchronous, active high), `i_write`, `i_read`, `i_address` (3 bits, word address), `i_data_in`, `o_data_out` and `o_irq`, plus the four pin ports of section 2. The registers are 32 bits wide and the block window spans 5 words.

## 4. Registers

| Word | Name | Access | Reset | Description |
| ---: | :--- | :--- | ---: | :--- |
| 0 | `TX_DATA` | W | n/a | Bits 7:0, byte queued for transmission; a write to a full queue is discarded and sets `TX_DROPPED` |
| 1 | `RX_DATA` | R | 0 | Bits 7:0, oldest received byte; the read removes it from the queue and returns zero when the queue is empty |
| 2 | `STATUS` | R/W1C | `0x6` | State and sticky flags (table below) |
| 3 | `CONTROL` | R/W | 0 | Chip select and interrupt enables (table below) |
| 4 | `DIVIDER` | R/W | section 3 | Bits 15:0, SCLK clock divider; takes effect at the next byte |

`STATUS` bits. Writing 1 to a W1C bit clears it, and a new event in the same cycle wins over the clear.

| Bit | Name | Access | Meaning |
| ---: | :--- | :--- | :--- |
| 0 | `RX_VALID` | R | The receive queue holds at least one byte |
| 1 | `TX_READY` | R | The transmit queue has room |
| 2 | `TX_EMPTY` | R | The transmit queue is empty (the last byte may still be in progress) |
| 3 | `BUSY` | R | A byte is in progress, has just finished, or the transmit queue is not empty |
| 4 | `RX_FULL` | R | The receive queue is full |
| 5 | `DONE` | W1C | A byte finished with the transmit queue empty |
| 6 | `RX_OVERRUN` | W1C | A received byte was discarded because the receive queue was full |
| 7 | `TX_DROPPED` | W1C | A write to `TX_DATA` was discarded because the queue was full |
| 15:8 | `RX_LEVEL` | R | Bytes in the receive queue |
| 23:16 | `TX_LEVEL` | R | Bytes in the transmit queue |

`CONTROL` bits.

| Bit | Name | Meaning |
| ---: | :--- | :--- |
| 0 | `CS_ASSERT` | When 1, the chip select line is driven low |
| 1 | `RX_IRQ_ENABLE` | Interrupt while the receive queue is not empty |
| 2 | `TX_EMPTY_IRQ_ENABLE` | Interrupt while the transmit queue is empty |
| 3 | `DONE_IRQ_ENABLE` | Interrupt while `DONE` is 1 |
| 4 | `ERROR_IRQ_ENABLE` | Interrupt while `RX_OVERRUN` or `TX_DROPPED` is 1 |

The `o_irq` output is a level and is the logical sum of the four enabled causes. The queue causes stop when the condition goes away (read of `RX_DATA`, write to `TX_DATA`), and the others stop when the software clears the flag.

## 5. Software use

Each byte written to `TX_DATA` produces one byte in `RX_DATA`, so the software reads one byte for every byte it sends. To only receive, it sends `0xFF`. Changing `CS_ASSERT` or `DIVIDER` is safe only with `BUSY` at zero, because the byte in progress still uses the previous value.

### 5.1. Initialization sequence

The card enters SPI mode when it receives CMD0 with the chip select low, and the sequence below is the one of the specification for an SDHC or SDXC card.

| Step | Action | Expected answer |
| ---: | :--- | :--- |
| 1 | With `CS_ASSERT` at 0 and SCLK at 400 kHz or less, send 10 bytes of `0xFF` (80 clocks, more than the required 74) | n/a |
| 2 | Set `CS_ASSERT` and send CMD0 (`0x40 0x00000000`, CRC `0x95`) | R1 `0x01` (idle) |
| 3 | CMD8 (`0x48 0x000001AA`, CRC `0x87`) | R1 `0x01` followed by 4 bytes whose low 12 bits are `0x1AA` |
| 4 | Repeat CMD55 (`0x77 0x00000000`) and ACMD41 (`0x69 0x40000000`) until the answer is R1 `0x00` | R1 `0x01` while initializing, then `0x00` |
| 5 | CMD58 (`0x7A 0x00000000`) | R1 `0x00` followed by the 4-byte OCR; bit 30 (CCS) at 1 means the address is the sector number |
| 6 | Raise the frequency by writing `DIVIDER` with `BUSY` at zero | n/a |

Every command is the byte `0x40 | index`, the 32-bit argument most significant byte first, and the CRC7 byte with bit 0 set to 1. After CMD0 and CMD8 the card ignores the CRC in SPI mode. The R1 answer arrives up to 8 bytes after the command, and until then the card returns `0xFF`.

### 5.2. Reading a sector (CMD17)

1. Send CMD17 with the sector number as argument and wait for R1 `0x00`.
2. Send `0xFF` until the token `0xFE` arrives.
3. Receive 512 data bytes and then 2 CRC16 bytes (polynomial $x^{16} + x^{12} + x^5 + 1$, initial value zero, most significant byte first).

### 5.3. Writing a sector (CMD24)

1. Send CMD24 with the sector number and wait for R1 `0x00`.
2. Send one `0xFF` byte, the token `0xFE`, the 512 data bytes and the 2 CRC16 bytes.
3. Receive the data response byte; the low 5 bits equal to `0x05` mean the data was accepted.
4. Send `0xFF` while the card returns `0x00` (busy) and proceed when it returns `0xFF`.

### 5.4. C example

The example initializes the card and reads one sector, in C23 with polling. The `SD_BASE` constant takes the block address on the platform.

```c
#include <stdbool.h>
#include <stdint.h>

/* Base address of the peripheral, set by the platform. */
#define SD_BASE ((volatile uint32_t *)0x40000000u)

enum { TX_DATA, RX_DATA, STATUS, CONTROL, DIVIDER };
enum { RX_VALID = 1u << 0, BUSY = 1u << 3 };
enum { CS_ASSERT = 1u << 0 };

#define SD_FAST_DIVIDER 1u /* SCLK = clock / 4 after initialization. */

/* Exchanges one byte and returns the received byte. */
static uint8_t spi_xfer(uint8_t value)
{
    SD_BASE[TX_DATA] = value;
    while ((SD_BASE[STATUS] & RX_VALID) == 0) {
    }
    return (uint8_t)SD_BASE[RX_DATA];
}

/* Sends a command and returns the R1, or 0xFF if the card does not answer. */
static uint8_t sd_command(uint8_t index, uint32_t argument, uint8_t crc)
{
    spi_xfer(0xFF);
    spi_xfer((uint8_t)(0x40u | index));
    for (int shift = 24; shift >= 0; shift -= 8) {
        spi_xfer((uint8_t)(argument >> shift));
    }
    spi_xfer(crc);
    uint8_t r1 = 0xFF;
    for (int attempt = 0; attempt < 8 && r1 == 0xFF; attempt++) {
        r1 = spi_xfer(0xFF);
    }
    return r1;
}

/* Initializes an SDHC card in SPI mode. Returns true on success. */
bool sd_init(void)
{
    SD_BASE[CONTROL] = 0; /* CS high */
    for (int i = 0; i < 10; i++) { /* 80 clocks, above the required 74 */
        spi_xfer(0xFF);
    }
    SD_BASE[CONTROL] = CS_ASSERT;

    if (sd_command(0, 0, 0x95) != 0x01) { /* CMD0 */
        return false;
    }
    if (sd_command(8, 0x1AA, 0x87) != 0x01) { /* CMD8 */
        return false;
    }
    uint32_t r7 = 0;
    for (int i = 0; i < 4; i++) {
        r7 = (r7 << 8) | spi_xfer(0xFF);
    }
    if ((r7 & 0xFFF) != 0x1AA) {
        return false;
    }

    uint8_t r1 = 0xFF;
    for (int attempt = 0; attempt < 100000 && r1 != 0x00; attempt++) {
        sd_command(55, 0, 0x65); /* CMD55 */
        r1 = sd_command(41, 0x40000000u, 0x77); /* ACMD41 with HCS */
    }
    if (r1 != 0x00) {
        return false;
    }

    if (sd_command(58, 0, 0xFD) != 0x00) { /* CMD58 */
        return false;
    }
    uint32_t ocr = 0;
    for (int i = 0; i < 4; i++) {
        ocr = (ocr << 8) | spi_xfer(0xFF);
    }
    if ((ocr & 0x40000000u) == 0) { /* CCS: the address is the sector number */
        return false;
    }

    SD_BASE[DIVIDER] = SD_FAST_DIVIDER;
    return true;
}

/* Reads the 512-byte sector into buffer. Returns true if the CRC16 matches. */
bool sd_read_sector(uint32_t sector, uint8_t buffer[static 512])
{
    if (sd_command(17, sector, 0xFF) != 0x00) { /* CMD17 */
        return false;
    }
    uint8_t token = 0xFF;
    for (int attempt = 0; attempt < 100000 && token == 0xFF; attempt++) {
        token = spi_xfer(0xFF);
    }
    if (token != 0xFE) {
        return false;
    }
    uint16_t crc = 0;
    for (int i = 0; i < 512; i++) {
        buffer[i] = spi_xfer(0xFF);
        crc ^= (uint16_t)buffer[i] << 8;
        for (int bit = 0; bit < 8; bit++) {
            crc = (crc & 0x8000u) ? (uint16_t)((crc << 1) ^ 0x1021u)
                                  : (uint16_t)(crc << 1);
        }
    }
    uint16_t received = (uint16_t)(spi_xfer(0xFF) << 8);
    received |= spi_xfer(0xFF);
    spi_xfer(0xFF);
    return received == crc;
}

/* Ends the access: waits for the master to stop and releases CS. */
void sd_release(void)
{
    while ((SD_BASE[STATUS] & BUSY) != 0) {
    }
    SD_BASE[CONTROL] = 0;
}
```

## 6. Verification

The entity test connects the peripheral to an SD card model in SPI mode that answers CMD0, CMD8, CMD55, ACMD41, CMD58, CMD17 and CMD24, and checks the CRC7 of CMD0 and CMD8, the CRC16 of the written sector and the initial 74 clocks with the chip select high. The cases cover reset, registers, the SCLK period for two dividers, initialization, sector read and write, queue overflow and each interrupt cause. The formal proof checks the `CONTROL` and `DIVIDER` registers, the chip select, the interrupt, the sticky flags, reset and the byte of eight SCLK edges, with mutants it must reject.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
