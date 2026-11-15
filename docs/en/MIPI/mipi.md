# MIPI CSI-2 camera receiver

🌐 [Português](../../pt-br/MIPI/mipi.md) · [English](../../en/MIPI/mipi.md)

## 1. Reference

The Arduino MKR Vidor 4000 (ABX00022) has a MIPI camera connector wired to LVDS pins of the 10CL016YU256C8G FPGA (Cyclone 10 LP). The board schematic terminates each differential pair with a 100 ohm resistor (R38, R39 and R40) and has no network that decodes the D-PHY low-power states. The pins below come from the board catalog of Insper-RISC-V (`boards/mkr-vidor-4000/pins.yaml`), which read them from the pin file of the Arduino reference project (`vidor_s_pins.qsf`, VidorBitstream) and checked them against the schematic.

| Signal | Pin | I/O standard | Direction, seen from the FPGA | Function |
| :--- | :--- | :--- | :--- | :--- |
| `iMIPI_D[0]` and `iMIPI_D[0](n)` | L2 and L1 | LVDS | input | Data lane 0 |
| `iMIPI_D[1]` and `iMIPI_D[1](n)` | J2 and J1 | LVDS | input | Data lane 1 |
| `iMIPI_CLK` and `iMIPI_CLK(n)` | M2 and M1 | LVDS | input | Clock lane |
| `bMIPI_SDA` and `bMIPI_SCL` | P2 and P1 | 2.5 V | bidirectional | I2C control of the camera (another peripheral) |
| `bMIPI_GP[0]` and `bMIPI_GP[1]` | M7 and P9 | 3.3 V LVTTL | bidirectional | General use of the connector, with no function fixed here |

The behavior expected on the FPGA side (two lanes, sampling on both edges of the clock lane, sync byte `0xB8` preceded by zeros, RAW8 image of data type 42 and I2C control) follows the `MIPI_RX_ST` IP of VidorBitstream, read as a reference for hardware facts with no code copied. The packet format (header, ECC and CRC-16) is that of MIPI CSI-2, and the physical layer is that of MIPI D-PHY, both specifications of the MIPI Alliance. The board facts come from the Arduino ABX00022 datasheet and schematic.

## 2. What it is

The peripheral receives the CSI-2 packets from one, two or four D-PHY lanes in high-speed mode. It finds the sync byte of each lane, aligns the bytes of the lanes, checks the header ECC and the CRC-16 of each line, separates the payload and writes a crop of the frame into a dual-clock memory that the processor reads over the bus. The payload bytes enter the memory as they arrive (RAW8, for example, stays as Bayer bytes), and the color conversion is left to the software.

The peripheral takes the input already sampled on both edges of the camera clock, two bits per lane and per cycle, which is the job of the input DDR register of the platform (`mipi_ddr_in`, with a simulation model and a wrapper of the `altddio_in` megafunction). It does not decode the low-power states of the D-PHY and does not configure the camera, which the software programs over I2C with the I2C peripheral of the platform.

| Generic | Default | Meaning |
| :--- | :--- | :--- |
| `lanes` | 2 | Number of data lanes, 1, 2 or 4 |
| `fb_line_bytes` | 256 | Bytes per line of the frame memory, a multiple of 4 |
| `fb_lines` | 128 | Lines of the frame memory |
| `default_dt` | 42 (`0x2A`, RAW8) | Data type of the stored lines after reset |

The memory has $\lceil fb\_line\_bytes \cdot fb\_lines / 4 \rceil$ 32-bit words. A line wider than `fb_line_bytes` loses its last bytes, and the lines after the last of `fb_lines` are discarded. A VGA RAW8 frame of $640 \times 480$ takes about 300 kB and does not fit in the memory blocks of the 10CL016, so the crop and the line step choose the part that is stored.

## 3. Interface

| Port | Direction | Function |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | System clock and synchronous reset, active at 1 |
| `i_write`, `i_read` | input | Write and read pulses of the processor |
| `i_address` | input | 4-bit word address |
| `i_data_in`, `o_data_out` | input, output | Write and read data (`word_t`); the registers use the low 32 bits |
| `o_irq` | output | Level interrupt, active at 1 |
| `i_mipi_clk` | input | Clock of the clock lane (`iMIPI_CLK`), asynchronous to `i_clk` |
| `i_mipi_early` | input | Older bit of the pair of each lane, sampled by `mipi_ddr_in` (one bit per lane) |
| `i_mipi_late` | input | Newer bit of the pair of each lane, sampled by `mipi_ddr_in` (one bit per lane) |

Lane $n$ of the peripheral is lane $n$ of the connector, and byte $k$ of a packet comes from lane $k \bmod lanes$.

## 4. Lane layer

Each lane keeps the last 24 bits received. While free, it looks for the byte `0xB8` (bits `00011101` sent from the least significant) preceded by at least 8 zero bits, in the two possible phases of the byte relative to the bit pair. Once it finds the sync, the lane delivers one aligned byte every four cycles of `i_mipi_clk`, and it unlocks only when the packet layer says so. The sync search does not run during a packet, so a `0xB8` inside the data does not affect the alignment.

## 5. Packet layer

### 5.1. Header

The header has 4 bytes: data identifier (virtual channel in bits 7 and 6, data type in bits 5 to 0), 16-bit word count (low byte first) and a 6-bit ECC. The ECC is the CSI-2 Hamming code over the first 24 bits, and a header whose ECC differs from the computed one is discarded without bit correction, because the packet size is unknown. The peripheral ignores the virtual channel and uses only the data type.

### 5.2. Packet types

| Data type | Packet | Handling |
| :--- | :--- | :--- |
| 0x00 | Frame start (short) | Starts the requested capture |
| 0x01 | Frame end (short) | Ends the capture |
| 0x02 and 0x03 | Line start and end (short) | Ignored |
| 0x04 to 0x0F | Other short packets | Ignored |
| 0x10 to 0x3F | Long packets | Stored if the data type is the one chosen in `CONFIG`, ignored otherwise |

A short packet has only the header, and the word count carries the 16-bit data (frame or line number). A long packet carries the payload of `word count` bytes and, after it, the CSI-2 CRC-16.

### 5.3. CRC

The CRC-16 uses the polynomial $x^{16} + x^{12} + x^5 + 1$, initial value `0xFFFF`, bits from the least significant, computed over the payload only and sent low byte first. A line with a wrong CRC is stored anyway and counts in the CRC error counter.

### 5.4. Packet end and skew

The packet size comes from the header, and at its end the lanes unlock and the sync search restarts. The last group of a packet can have fewer bytes than lanes. The accepted skew between lanes is up to 3 cycles of `i_mipi_clk`. If only part of the lanes align and the others do not align within 8 cycles, the search restarts.

## 6. Capturing a frame

With the receiver enabled, the software writes `START`, and the capture waits for a frame start packet. Each line of the chosen data type enters the memory from the top left corner, one memory line per stored line, and the frame end packet ends the capture. The line step $s$ stores one line out of every $s$ among the lines of the chosen type, starting with the first.

| Situation | Result |
| :--- | :--- |
| Frame end with at least one stored line | Frame ready (`READY`) and frame counter incremented |
| Frame start in the middle of the capture, or frame end with no stored line | Capture ended with no frame ready, with `ERROR` |
| Line with bytes beyond `fb_line_bytes`, or line beyond `fb_lines` | Bytes and lines discarded, added to the drop counter of `ERRORS` |
| Header with a wrong ECC | Packet lost, added to the ECC counter of `ERRORS`, with `ERROR` |
| Line with a wrong CRC | Line stored, added to the CRC counter of `ERRORS`, with `ERROR` |

The configuration (`CONFIG`) accepts writes only while the capture is stopped. Writing 0 to `ENABLE` ends the capture and resets the camera clock domain on the next edge of `i_mipi_clk`.

## 7. Register map

Accesses are 32 bits wide, and the address is a word address. An address outside the map reads zero and ignores writes.

| Address | Register | Access | Reset | Description |
| :--- | :--- | :--- | :--- | :--- |
| 0 | `CTRL` | R/W | 0 | Control |
| 1 | `STATUS` | R/W (writing 1 clears) | 0 | Status |
| 2 | `FRAME_COUNT` | R | 0 | Complete frames captured since reset |
| 3 | `CONFIG` | R/W | `0x012A` | Data type and line step |
| 4 | `GEOMETRY` | R | from the generics | Lines in bits 31 to 16 and bytes per line in bits 15 to 0 |
| 5 | `RD_ADDR` | R/W | 0 | Word pointer of the frame memory read |
| 6 | `RD_DATA` | R | 0 | Word under the pointer, with the pointer incremented on each read |
| 7 | `LAST_FRAME` | R | 0 | Lines stored in the last frame (bits 15 to 0) and word count of the last line (bits 31 to 16) |
| 8 | `ERRORS` | R/W (writing zeroes) | 0 | ECC (bits 7 to 0), CRC (bits 15 to 8) and drop (bits 23 to 16) counters, saturating at 255 |
| 9 | `INFO` | R | from the generics | Number of lanes in bits 3 to 0 |

### 7.1. `CTRL`

| Bit | Name | Description |
| :--- | :--- | :--- |
| 0 | `START` | Writing 1 with `ENABLE` at 1 and the capture stopped requests a frame; always reads 0 |
| 1 | `FRAME_IE` | Interrupt while `READY` is 1 |
| 2 | `ERROR_IE` | Interrupt while `ERROR` is 1 |
| 3 | `ENABLE` | Enables the receiver; at 0, the camera clock domain stays in reset |

`ENABLE` must be written before `START`, in separate accesses.

### 7.2. `STATUS`

| Bit | Name | Description |
| :--- | :--- | :--- |
| 0 | `BUSY` | Capture in progress, from the write of `START` to the frame end |
| 1 | `READY` | Frame ready; stays at 1 until 1 is written to the bit or another capture starts |
| 2 | `ERROR` | ECC error, CRC error or incomplete frame; stays at 1 until 1 is written to the bit |
| 3 | `SEEN` | At least one header with a correct ECC has arrived since `ENABLE` was written to 1 |

### 7.3. `CONFIG`

| Bits | Field | Description |
| :--- | :--- | :--- |
| 5:0 | `dt` | Data type of the stored lines |
| 15:8 | `y_step` | Line step; zero counts as one |

### 7.4. Reading the frame memory

Each word of `RD_DATA` holds four memory bytes, the lowest-addressed byte in bits 7 to 0. Word $w$ covers bytes $4w$ to $4w + 3$ of the frame, and line $r$ starts at word $r \cdot fb\_line\_bytes / 4$. Writing to `RD_ADDR` a value greater than the last word is ignored, and reading the last word takes the pointer back to 0.

## 8. Interrupt

$$o\_irq = (FRAME\_IE \wedge READY) \vee (ERROR\_IE \wedge ERROR)$$

The output is a level and drops when the software writes 1 to the matching bit of `STATUS`.

## 9. Clocks and constraints

`i_clk` and `i_mipi_clk` are asynchronous to each other. The capture request and the enable cross through two-stage synchronizers toward the camera clock, and the capture end, the errors and the `SEEN` state cross the other way, the events as toggles. The capture result, the data type and the line step are vectors held still when the toggle reveals them, and the board constraints file must cut them with `set_false_path`. The system clock must be faster than one twelfth of `i_mipi_clk`, so that two errors in a row do not merge into one toggle.

The rate of each lane is twice the frequency of `i_mipi_clk`, and the peripheral logic runs on `i_mipi_clk`. The maximum frequency the logic closes on the board is a matter of timing analysis in the platform.

## 10. Limits

| Item | Situation |
| :--- | :--- |
| D-PHY low-power states | Not seen; the receiver depends on zeros and `0xB8` to find the start of each burst and on the packet size to find its end |
| ECC correction | None; a header with a wrong ECC drops the packet |
| Virtual channel | Ignored |
| Formats | Payload bytes enter unconverted; RAW10, RAW12 and packed formats stay packed in the memory |
| Whole frame | Only the top left crop, with a line step; the memory is made of FPGA blocks |
| Packet interrupted midway | The receiver waits for the size in the header; `ENABLE` at 0 restarts |
| Electrical suitability of the pins | High-speed D-PHY reaches LVDS pins of the FPGA, as in the Arduino reference project; the level compatibility with the camera used was not checked on the bench |

## 11. C example

The program enables the receiver, captures a frame and reads the first line. The window base comes from the header generated from `platform.yaml`.

```c
#include <stdint.h>
#include <stdio.h>

enum { MIPI_CTRL, MIPI_STATUS, MIPI_FRAME_COUNT, MIPI_CONFIG, MIPI_GEOMETRY,
       MIPI_RD_ADDR, MIPI_RD_DATA };

enum : uint32_t {
    CTRL_START = 1u << 0,
    CTRL_ENABLE = 1u << 3,
    STAT_BUSY = 1u << 0,
    STAT_READY = 1u << 1,
};

void capture_first_line(volatile uint32_t *mipi) {
    mipi[MIPI_CTRL] = CTRL_ENABLE;
    mipi[MIPI_CTRL] = CTRL_ENABLE | CTRL_START;
    while (mipi[MIPI_STATUS] & STAT_BUSY) {
    }
    if (!(mipi[MIPI_STATUS] & STAT_READY)) {
        return;
    }
    uint32_t line_bytes = mipi[MIPI_GEOMETRY] & 0xFFFFu;
    mipi[MIPI_RD_ADDR] = 0;
    for (uint32_t word = 0; word < line_bytes / 4; word++) {
        printf("%08x\n", (unsigned)mipi[MIPI_RD_DATA]);
    }
    mipi[MIPI_STATUS] = STAT_READY;
}
```

## 12. Verification

The entity tests cover the lane (the two byte phases, every bit offset, preamble, `0xB8` in the data and unlocking), the packet layer (short packets, payloads of 0 to 33 bytes with 1, 2 and 4 lanes, wrong CRC and ECC, the ECC reference vector, skew between lanes and search restart), the capture control (frame, crop, line step, data type filter, aborts and events) and the registers (status, counters, configuration lock and pointer). The test of the full block generates CSI-2 frames bit by bit, with a different skew and phase for each packet, and reads them over the bus with 1, 2 and 4 lanes. The tests are simulations, and the peripheral was not exercised on a real camera. The formal verification flow of the repository has no proofs for this peripheral.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
