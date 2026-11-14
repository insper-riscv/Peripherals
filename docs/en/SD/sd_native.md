# SD card controller in native mode

🌐 [Português](../../pt-br/SD/sd_native.md) · [English](../../en/SD/sd_native.md)

## 1. What it is

A bus peripheral that drives an SD or micro SD card in native mode, with one or four data lines, the mode in which the card reaches its maximum transfer rate. The software writes the argument and the command, the peripheral sends the 48-bit frame with its CRC7, receives and checks the response and, when the command carries a block, moves the 512 bytes between the card and a block buffer with one CRC16 per line. The SPI mode of the same card is described in [sd_spi.md](sd_spi.md).

The peripheral is made of seven blocks.

| Block | Function |
| :--- | :--- |
| `sd_clock_gen` | Generates `SD_CLK` from a divider and the pulses that precede each edge; the clock runs only on request |
| `sd_cmd` | Controls the `CMD` line: sends the command, receives the short (48-bit) and long (136-bit) responses, checks CRC7, index and end bit, and waits for the end of the busy signal on `DAT0` |
| `sd_data` | Controls the `DAT[3:0]` lines: reads or writes the 512-byte block with one or four lines, computes and checks the CRC16 of each line, receives the CRC status and waits for the end of the busy signal |
| `sd_crc7` | Serial CRC7 register with polynomial $x^7 + x^3 + 1$, used by `sd_cmd` |
| `sd_crc16` | Serial CRC16 register with polynomial $x^{16} + x^{12} + x^5 + 1$, one instance per data line |
| `sd_block_buffer` | Memory of 128 words of 32 bits with one write port and one read port, implemented in block RAM |
| `sd_native` | Top level with the registers, the persistent flags, the buffer window, the input synchronization and the interrupt |

## 2. Pins and boards

The DE0-CV socket and the DE2-115 socket connect the card to the FPGA at 3.3 V, with the four data lines, the command and the clock. The DE0-CV manual (section 3.8) says the socket offers the SPI and the 4-bit SD modes, and the DE2-115 manual (section 4.19) lists the same signals. The boards have no card-detect pin (the DE2-115 has only the write-protect one, `SD_WP_N`).

| Peripheral port | Direction | Function | DE0-CV pin | DE2-115 pin |
| :--- | :--- | :--- | :--- | :--- |
| `o_sd_clk` | output | Card clock | `SD_CLK` (`PIN_H11`) | `SD_CLK` (`PIN_AE13`) |
| `o_sd_cmd`, `o_sd_cmd_oe`, `i_sd_cmd` | output, enable, input | Command and response | `SD_CMD` (`PIN_B11`) | `SD_CMD` (`PIN_AD14`) |
| `o_sd_dat(0)`, `o_sd_dat_oe(0)`, `i_sd_dat(0)` | output, enable, input | Data 0, which also signals busy | `SD_DATA0` (`PIN_K9`) | `SD_DAT[0]` (`PIN_AE14`) |
| `o_sd_dat(1)`, `o_sd_dat_oe(1)`, `i_sd_dat(1)` | output, enable, input | Data 1 | `SD_DATA1` (`PIN_D12`) | `SD_DAT[1]` (`PIN_AF13`) |
| `o_sd_dat(2)`, `o_sd_dat_oe(2)`, `i_sd_dat(2)` | output, enable, input | Data 2 | `SD_DATA2` (`PIN_E12`) | `SD_DAT[2]` (`PIN_AB14`) |
| `o_sd_dat(3)`, `o_sd_dat_oe(3)`, `i_sd_dat(3)` | output, enable, input | Data 3 | `SD_DATA3` (`PIN_C11`) | `SD_DAT[3]` (`PIN_AC14`) |

The platform top level connects each bidirectional pin to its triple of ports with a tristate buffer, so the pin takes the output value when the enable is 1 and floats when it is 0. With one data line only `DAT0` is enabled, and the others stay as inputs.

$$ \text{pin} = \begin{cases} \text{o\_sd\_cmd} & \text{if o\_sd\_cmd\_oe} = 1 \\ Z & \text{otherwise} \end{cases} $$

## 3. Parameters and ports

| Parameter | Default | Meaning |
| :--- | ---: | :--- |
| `clock_hz` | 50000000 | Frequency of the module clock, in hertz |
| `init_clk_hz` | 400000 | Frequency of `SD_CLK` after reset; card identification requires at most 400 kHz |
| `default_timeout` | 2500000 | Value of `TIMEOUT` after reset, in card clocks |
| `input_sync_stages` | 1 | Flip-flops in series on the input lines; each extra stage requires a larger minimum divider |

The reset divider is

$$ \text{DIVIDER}_{reset} = \left\lceil \frac{\text{clock\_hz}}{2 \cdot \text{init\_clk\_hz}} \right\rceil - 1 $$

and the card clock frequency is

$$ f_{SD\_CLK} = \frac{\text{clock\_hz}}{2 \cdot (\text{DIVIDER} + 1)} $$

With a 50 MHz `clock_hz`, divider 0 gives the 25 MHz of the default speed mode. The input lines are read through a single register stage, because the card changes the data right after the rising edge of `SD_CLK` and the peripheral samples it at the next rising edge, more than half a period later. With `input_sync_stages` equal to $n$, the minimum divider becomes $n - 1$.

The bus ports are `i_clk`, `i_rst` (synchronous, active high), `i_write`, `i_read`, `i_address` (4 bits, word address), `i_data_in`, `o_data_out` and `o_irq`, plus the pin ports of section 2. The registers are 32 bits wide and the block window spans 13 words.

## 4. Registers

| Word | Name | Access | Reset | Description |
| ---: | :--- | :--- | ---: | :--- |
| 0 | `ARG` | R/W | 0 | 32-bit argument of the next command |
| 1 | `CMD` | R/W | 0 | A write starts a command (bits below); a read returns the last accepted value |
| 2 | `RESP0` | R | 0 | Short response, the 32 argument bits (R1, R3, R6, R7); long response, bits 39 to 8 of the CID or CSD |
| 3 | `RESP1` | R | 0 | Short response, bits 5 to 0 with the response index; long response, bits 71 to 40 |
| 4 | `RESP2` | R | 0 | Long response, bits 103 to 72 |
| 5 | `RESP3` | R | 0 | Long response, bits 127 to 104 in bits 23 to 0 |
| 6 | `STATUS` | R/W1C | `0xF20` with idle lines | State and completion flags (table below) |
| 7 | `ERROR` | R/W1C | 0 | Persistent errors (table below) |
| 8 | `CONTROL` | R/W | 0 | Clock, bus width and interrupt enables |
| 9 | `DIVIDER` | R/W | section 3 | Bits 15 to 0, divider of `SD_CLK`; takes effect from the next half period |
| 10 | `TIMEOUT` | R/W | `default_timeout` | Bits 23 to 0, wait limit for data and for busy, in card clocks |
| 11 | `DATA` | R/W | 0 | Buffer word pointed to by `PTR`; each read or write advances `PTR` |
| 12 | `PTR` | R/W | 0 | Bits 6 to 0, buffer word pointed to; a write selects the word and the pointer wraps after 127 |

Bits of `CMD`. The command frame uses the index, the argument of `ARG` and the CRC7 computed by the peripheral.

| Bits | Name | Meaning |
| ---: | :--- | :--- |
| 5 to 0 | `INDEX` | Command index |
| 7 to 6 | `RESPONSE` | Expected format, 0 none, 1 short with CRC7 and index checked (R1, R1b, R6, R7), 2 short without checks (R3), 3 long of 136 bits (R2) |
| 8 | `WAIT_BUSY` | After the response, waits for `DAT0` to return to 1 (R1b) |
| 9 | `DATA_EN` | The command carries a 512-byte block, moved by the data controller |
| 10 | `DATA_WRITE` | Block direction, 0 reads from the card into the buffer and 1 writes from the buffer to the card |

A write to `CMD` while a command or a transfer is in progress is refused and sets `DROPPED` in `ERROR`. Bits of `STATUS`; writing 1 to a W1C bit clears it, and a new event in the same cycle wins over the clear.

| Bit | Name | Access | Meaning |
| ---: | :--- | :--- | :--- |
| 0 | `CMD_BUSY` | R | A command is in progress |
| 1 | `DATA_BUSY` | R | A block transfer is in progress or waiting for the command response |
| 2 | `CMD_DONE` | W1C | The command ended, with or without error; a new command clears the flag |
| 3 | `DATA_DONE` | W1C | The transfer ended, with or without error; it also rises when a refused response cancels the block |
| 4 | `CARD_BUSY` | R | `DAT0` is low, the card is busy |
| 5 | `CMD_LINE` | R | Level of the `CMD` line |
| 11 to 8 | `DAT_LINES` | R | Levels of `DAT3` to `DAT0` |
| 18 to 16 | `WRITE_TOKEN` | R | CRC status returned by the card in the last block write |

Bits of `ERROR`, all W1C.

| Bit | Name | Cause |
| ---: | :--- | :--- |
| 0 | `CMD_TIMEOUT` | The response did not arrive within 64 clocks, or `DAT0` stayed busy beyond `TIMEOUT` after an R1b response |
| 1 | `CMD_CRC` | The CRC7 of the response does not match |
| 2 | `CMD_INDEX` | The index of the response differs from the command index |
| 3 | `CMD_FRAME` | The transmission bit or the end bit of the response has the wrong value |
| 4 | `DATA_TIMEOUT` | The block start bit did not arrive within `TIMEOUT` clocks, the CRC status did not arrive within 16 clocks, or the busy signal exceeded `TIMEOUT` |
| 5 | `DATA_CRC` | The CRC16 of some line of the block read does not match |
| 6 | `DATA_FRAME` | The start bit or the end bit of the block, or the end bit of the CRC status, has the wrong value |
| 7 | `WRITE_CRC` | The card returned CRC status 101, a CRC error in the data |
| 8 | `WRITE_ERROR` | The card returned a CRC status other than 010 and 101 |
| 9 | `DROPPED` | A write to `CMD` was refused because an operation was in progress |

Bits of `CONTROL`.

| Bit | Name | Meaning |
| ---: | :--- | :--- |
| 0 | `CLK_ENABLE` | Keeps `SD_CLK` running, for the 74 initialization clocks |
| 1 | `WIDE_BUS` | Blocks use the four lines; with 0, only `DAT0` |
| 2 | `CMD_IRQ_ENABLE` | Interrupt while `CMD_DONE` is 1 |
| 3 | `DATA_IRQ_ENABLE` | Interrupt while `DATA_DONE` is 1 |
| 4 | `ERROR_IRQ_ENABLE` | Interrupt while any bit of `ERROR` is 1 |
| 8 | `ABORT` | Writing 1 interrupts the command and the transfer in progress and releases the lines; the bit is not stored |

The `o_irq` output is level-sensitive and is the logical OR of the three enabled causes, and each one drops only when the software clears the matching flag.

## 5. Protocol

### 5.1. Command frame

The command has 48 bits sent on the `CMD` line, most significant first, with the bits leaving on the falling edge of `SD_CLK` and the card sampling them on the rising edge.

| Bits | Field | Value |
| ---: | :--- | :--- |
| 47 | Start | 0 |
| 46 | Transmission | 1, direction from the host to the card |
| 45 to 40 | Index | Command index |
| 39 to 8 | Argument | Contents of `ARG` |
| 7 to 1 | CRC7 | Remainder of the division of the first 40 bits by $x^7 + x^3 + 1$, initial value zero |
| 0 | End | 1 |

After the end bit the peripheral releases the line. Then 8 clocks pass before the command ends, and with `WAIT_BUSY` the peripheral also waits for `DAT0` to return to 1.

### 5.2. Responses

The response arrives on the `CMD` line, and the peripheral waits for the start bit for at most 64 clocks after the command.

| Format | Bits | Contents | Check |
| :--- | ---: | :--- | :--- |
| R1, R1b, R6, R7 (`RESPONSE` 1) | 48 | Start 0, transmission 0, 6-bit index, 32-bit argument, CRC7, end 1 | CRC7 over the first 40 bits, index equal to the command index, transmission and end |
| R3 (`RESPONSE` 2) | 48 | Start 0, transmission 0, six bits at 1, argument (the OCR), seven bits at 1, end 1 | Only transmission and end, since CRC7 and index have no defined value |
| R2 (`RESPONSE` 3) | 136 | Start 0, transmission 0, six bits at 1, 120 bits of CID or CSD, register CRC7, end 1 | CRC7 over the 120 CID or CSD bits, transmission and end |

In short responses `RESP0` holds the argument and `RESP1` holds the index in bits 5 to 0. In the long one, the four words hold bits 127 to 8 of the register, without the CRC7 and the end bit.

### 5.3. Data block

A block has 512 bytes. With four lines each clock carries one nibble, the most significant nibble of the byte first, with `DAT3` on the most significant bit of the nibble, and each line has its own CRC16. With one line each clock carries one bit of `DAT0`.

| Phase | Four lines | One line |
| :--- | :--- | :--- |
| Start | 1 clock with `DAT[3:0]` at 0 | 1 clock with `DAT0` at 0 |
| Data | 1024 clocks | 4096 clocks |
| CRC16 | 16 clocks, the CRC of each line, most significant bit first | 16 clocks of `DAT0` |
| End | 1 clock with `DAT[3:0]` at 1 | 1 clock with `DAT0` at 1 |

The CRC16 of each line covers the bits that went through it, with polynomial $x^{16} + x^{12} + x^5 + 1$ and initial value zero. The first byte of the block occupies bits 7 to 0 of buffer word 0, the second bits 15 to 8, and so on.

On a read the card sends the block after the response, and the peripheral waits for the start bit for `TIMEOUT` clocks. On a write the peripheral waits 4 clocks after the response, sends the block, releases the lines and receives the CRC status on `DAT0`, with start 0, three bits and end 1, up to 16 clocks after the block.

| CRC status | Meaning | Effect |
| :--- | :--- | :--- |
| 010 | Block accepted | No error |
| 101 | CRC error in the data | `WRITE_CRC` |
| 110 | Write error | `WRITE_ERROR` |

After the CRC status the peripheral waits 2 clocks and then waits for `DAT0` to return to 1, the end of programming, for at most `TIMEOUT` clocks.

### 5.4. Timing

| Wait | Value | Use |
| :--- | ---: | :--- |
| Identification frequency | up to 400 kHz | From reset until the width and speed are chosen |
| Transfer frequency | up to 25 MHz | Divider 0 with the 50 MHz clock |
| Clocks before CMD0 | at least 74 and 1 ms | The software turns on `CLK_ENABLE` for the time needed |
| Response (NCR) | at most 64 clocks | Limit for the start bit of the response |
| Between commands (NCC) | at least 8 clocks | Interval the peripheral adds at the end of each command |
| Response to the written block (NWR) | at least 2 clocks | The peripheral waits 4 |
| CRC status | 2 clocks after the block | The peripheral accepts up to 16 |

## 6. Use by the software

### 6.1. Initialization sequence

The sequence is the one in the specification for an SDHC or SDXC card, with `CMD` written already with the format bits.

| Step | Action | Expected response |
| ---: | :--- | :--- |
| 1 | With `DIVIDER` at its reset value, turn on `CLK_ENABLE`, wait 1 ms and turn it off | At least 74 clocks with `CMD` at 1 |
| 2 | CMD0 with argument 0, no response | None |
| 3 | CMD8 with `0x000001AA`, response 1 | Echo `0x1AA` in `RESP0` |
| 4 | Repeat CMD55 with argument 0 (response 1) and ACMD41 with `0x40FF8000` (response 2) until bit 31 of `RESP0` is 1 | Bit 30 (CCS) at 1 for sector addressing |
| 5 | CMD2 with response 3 | CID in the four response words |
| 6 | CMD3 with response 1 | `RESP0` bits 31 to 16 with the RCA |
| 7 | CMD7 with the RCA in bits 31 to 16 and `WAIT_BUSY` | Card in the transfer state |
| 8 | CMD55 with the RCA and ACMD6 with argument 2, then `WIDE_BUS` in `CONTROL` | Four data lines |
| 9 | Write the transfer divider to `DIVIDER` | `SD_CLK` at the final speed |

### 6.2. Reading and writing a sector

To read, the software writes `ARG` with the sector number and `CMD` with CMD17, response 1 and `DATA_EN`, waits for `CMD_DONE` and `DATA_DONE`, checks `ERROR`, points `PTR` to 0 and reads 128 words from `DATA`. To write, it points `PTR` to 0, writes 128 words to `DATA`, writes `ARG` with the sector and `CMD` with CMD24, response 1, `DATA_EN` and `DATA_WRITE`, waits for both flags and checks `ERROR` and the `WRITE_TOKEN` of `STATUS`. While `DATA_BUSY` is set the software does not access `DATA`, because the data controller owns the buffer. Each block command carries a single 512-byte block.

### 6.3. C example

The example initializes the card, reads a sector and writes it back, with C23 and polling. The `SD_BASE` constant takes the address of the block on the platform, and `delay_us` is the platform delay.

```c
#include <stdbool.h>
#include <stdint.h>

/* Peripheral base, defined by the platform. */
#define SD_BASE ((volatile uint32_t *)0x40000000u)

/* Platform delay, in microseconds. */
extern void delay_us(uint32_t microseconds);

enum {
    ARG, CMD, RESP0, RESP1, RESP2, RESP3, STATUS, ERROR,
    CONTROL, DIVIDER, TIMEOUT, DATA, PTR
};
enum {
    CMD_DONE = 1u << 2,
    DATA_DONE = 1u << 3,
    TOKEN_SHIFT = 16,
    TOKEN_MASK = 0x7u,
    TOKEN_ACCEPTED = 0x2u
};
enum { CLK_ENABLE = 1u << 0, WIDE_BUS = 1u << 1 };
enum {
    RSP_NONE = 0u << 6, RSP_R1 = 1u << 6, RSP_R3 = 2u << 6, RSP_R2 = 3u << 6,
    WAIT_BUSY = 1u << 8, DATA_EN = 1u << 9, DATA_WRITE = 1u << 10
};

#define SD_FAST_DIVIDER 0u /* 25 MHz with the 50 MHz clock. */
#define SD_WORDS 128u

/* Waits for every bit of mask in STATUS. */
static void sd_wait(uint32_t mask)
{
    while ((SD_BASE[STATUS] & mask) != mask) {
    }
}

/* Reads and clears ERROR; returns zero when everything went well. */
static uint32_t sd_take_errors(void)
{
    uint32_t errors = SD_BASE[ERROR];
    SD_BASE[ERROR] = errors;
    return errors;
}

/* Sends a command and returns the errors. */
static uint32_t sd_command(uint32_t index, uint32_t argument, uint32_t flags)
{
    SD_BASE[ARG] = argument;
    SD_BASE[CMD] = index | flags;
    sd_wait(CMD_DONE);
    SD_BASE[STATUS] = CMD_DONE;
    return sd_take_errors();
}

/* Sends CMD55 and then the application command. */
static uint32_t sd_app_command(uint32_t rca, uint32_t index, uint32_t argument,
                               uint32_t flags)
{
    uint32_t errors = sd_command(55, rca << 16, RSP_R1);
    return errors | sd_command(index, argument, flags);
}

/* Initializes an SDHC card and leaves it in the transfer state with four
 * lines. Returns true on success. */
bool sd_init(void)
{
    SD_BASE[CONTROL] = CLK_ENABLE; /* 74 clocks or more with CMD at 1 */
    delay_us(1000);
    SD_BASE[CONTROL] = 0;

    if (sd_command(0, 0, RSP_NONE) != 0) { /* CMD0 */
        return false;
    }
    if (sd_command(8, 0x1AA, RSP_R1) != 0 || (SD_BASE[RESP0] & 0xFFF) != 0x1AA) {
        return false; /* CMD8 */
    }

    uint32_t ocr = 0;
    for (int attempt = 0; attempt < 1000 && (ocr & 0x80000000u) == 0; attempt++) {
        if (sd_app_command(0, 41, 0x40FF8000u, RSP_R3) != 0) { /* ACMD41 */
            return false;
        }
        ocr = SD_BASE[RESP0];
        delay_us(1000);
    }
    if ((ocr & 0xC0000000u) != 0xC0000000u) { /* ready and CCS */
        return false;
    }

    if (sd_command(2, 0, RSP_R2) != 0) { /* CMD2, CID in RESP0 to RESP3 */
        return false;
    }
    if (sd_command(3, 0, RSP_R1) != 0) { /* CMD3 */
        return false;
    }
    uint32_t rca = SD_BASE[RESP0] >> 16;
    if (sd_command(7, rca << 16, RSP_R1 | WAIT_BUSY) != 0) { /* CMD7 */
        return false;
    }
    if (sd_app_command(rca, 6, 2, RSP_R1) != 0) { /* ACMD6, four lines */
        return false;
    }
    SD_BASE[CONTROL] = WIDE_BUS;
    SD_BASE[DIVIDER] = SD_FAST_DIVIDER;
    return true;
}

/* Reads the 512-byte sector into buffer. Returns true if there was no error. */
bool sd_read_sector(uint32_t sector, uint32_t buffer[static SD_WORDS])
{
    SD_BASE[ARG] = sector;
    SD_BASE[CMD] = 17 | RSP_R1 | DATA_EN;
    sd_wait(CMD_DONE | DATA_DONE);
    SD_BASE[STATUS] = CMD_DONE | DATA_DONE;
    if (sd_take_errors() != 0) {
        return false;
    }
    SD_BASE[PTR] = 0;
    for (uint32_t i = 0; i < SD_WORDS; i++) {
        buffer[i] = SD_BASE[DATA];
    }
    return true;
}

/* Writes the 512-byte sector from buffer. Returns true if the card accepted it. */
bool sd_write_sector(uint32_t sector, const uint32_t buffer[static SD_WORDS])
{
    SD_BASE[PTR] = 0;
    for (uint32_t i = 0; i < SD_WORDS; i++) {
        SD_BASE[DATA] = buffer[i];
    }
    SD_BASE[ARG] = sector;
    SD_BASE[CMD] = 24 | RSP_R1 | DATA_EN | DATA_WRITE;
    sd_wait(CMD_DONE | DATA_DONE);
    uint32_t token = (SD_BASE[STATUS] >> TOKEN_SHIFT) & TOKEN_MASK;
    SD_BASE[STATUS] = CMD_DONE | DATA_DONE;
    return sd_take_errors() == 0 && token == TOKEN_ACCEPTED;
}
```

## 7. Source of the information

The SD Physical Layer specification is not among the documents of the repository, and what this peripheral implements comes from the author's knowledge of it, without a check against the text of the specification. The data that came from the board manuals are the names and pins of section 2 and the mention of the SPI and 4-bit SD modes of the DE0-CV.

| Information | Source |
| :--- | :--- |
| 48-bit command frame, CRC7 and CRC16 polynomials, formats R1, R1b, R2, R3, R6 and R7 | SD specification, from memory |
| Known CRC values (CMD0 `0x4A`, CMD8 `0x43`, CMD17 `0x2A`, CMD55 `0x32`, ACMD41 `0x3B`, 512 bytes of `0xFF` with `0x7FA1`) | SD specification, from memory, checked against the independent computation of the test |
| Sequence CMD0, CMD8, ACMD41, CMD2, CMD3, CMD7, ACMD6, the CCS and OCR bits, argument `0x1AA` | SD specification, from memory |
| Waits of 74 clocks, 400 kHz, 25 MHz, NCR 64, NCC 8, NWR 2 and the CRC status | SD specification, from memory; the design values (8, 4, 16 and 2 clocks) belong to the peripheral |
| CRC statuses 010, 101 and 110 and the busy signal on `DAT0` | SD specification, from memory |
| Pins, voltage and modes of the socket | DE0-CV and DE2-115 manuals in `Docs` |
| Test on a real card | Not confirmed; the verification uses only the card model of the test |

## 8. Verification

The entity test connects the peripheral to a native-mode SD card model that answers CMD0, CMD8, CMD55, ACMD41, CMD2, CMD3, CMD7, ACMD6, CMD13, CMD17 and CMD24, with CRC7 and CRC16 computed by polynomial division of integers, independently of the shift register of the VHDL. The model checks the CRC7 of each command, the initial 74 clocks and the CRC16 of each line of the written block, and accepts injected faults (missing response, wrong CRC or index, corrupted or missing block, CRC status 101 and 110, stuck busy). The cases cover the reset, the registers, the period of `SD_CLK` and its stop when idle, the full initialization up to reading and writing a sector with four lines and with one, dividers 0 to 2, the timeout without a card, each response check, busy detection on `DAT0`, each data error, the refused command, the abort and the interrupts. The tests of the two CRCs and of the clock generator run separately, and the CRC one compares the register with known values and with random messages.

The formal proof checks the CRC7 and the CRC16 against the polynomial division and against a known value, the zero remainder of a message followed by its own CRC, and the command controller: the 48-bit frame with its CRC7, the response timeout, the acceptance and refusal of each short response format, the busy wait and the abort, with mutants it must reject.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
