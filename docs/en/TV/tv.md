# TV decoder video capture

🌐 [Português](../../pt-br/TV/tv.md) · [English](../../en/TV/tv.md)

## 1. Reference

The DE2-115 board carries the ADV7180 TV decoder, which converts baseband analog video (NTSC, PAL or SECAM) into 4:2:2 video in the 8-bit ITU-R BT.656 standard. The chip is configured over I2C (write address 0x40 and read address 0x41, section 4.15 of the board manual) and delivers the video to the FPGA on the pins below.

| Signal | Pin | Direction, seen from the FPGA | Function |
| :--- | :--- | :--- | :--- |
| `TD_DATA[0]` to `TD_DATA[7]` | E8, A7, D8, C7, D7, D6, E7, F7 | input | Byte of the BT.656 stream |
| `TD_CLK27` | B14 | input | 27 MHz clock of the stream |
| `TD_HS`, `TD_VS` | E5, E4 | input | Decoder syncs, unused: the peripheral reads the sync from the codes embedded in the stream |
| `TD_RESET_N` | G7 | output | Decoder reset, active low |

## 2. What it is

The peripheral receives the BT.656 stream, recognizes the start and the end of the active video of each line, extracts the luma Y and the chroma Cb and Cr, converts each pixel to 16-bit RGB (RGB565) or to 8-bit luma, drops pixels to reduce the resolution by integer factors and writes a frame into a two-clock memory. The processor reads the frame over the bus once the peripheral signals that it is ready. The peripheral does not speak I2C: the software programs the ADV7180 with the platform's I2C peripheral.

| Generic | Default | Meaning |
| :--- | :--- | :--- |
| `fb_width` | 160 | Width of the frame memory in pixels |
| `fb_height` | 120 | Height of the frame memory in pixels |
| `src_width` | 720 | Width in pixels of the source area captured, from the top left corner (720 for NTSC) |
| `src_height` | 480 | Height in lines of the source area captured, counting both fields (480 for NTSC) |
| `check_protection` | `true` | Checks the four protection bits of every timing code |
| `present_cycles` | 4096 | `TD_CLK27` cycles without a valid code after which the video is taken as absent |

The frame fits in the memory if $\lceil \text{src\_width} / x \rceil \le \text{fb\_width}$ and $\lceil \text{src\_height} / y \rceil \le \text{fb\_height}$ for the decimation factors $x$ and $y$ chosen; anything beyond that is discarded.

## 3. Interface

| Port | Direction | Function |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | System clock and synchronous reset, active at 1 |
| `i_write`, `i_read` | input | Write and read pulses of the processor |
| `i_address` | input | 4-bit word address |
| `i_data_in`, `o_data_out` | input, output | Write and read data (`word_t`); the registers use the low 32 bits |
| `o_irq` | output | Level interrupt, active at 1 |
| `i_td_clk27` | input | `TD_CLK27`, asynchronous to `i_clk` |
| `i_td_data` | input | `TD_DATA[7:0]` |
| `o_td_reset_n` | output | `TD_RESET_N`, driven by the `DECODER_RUN` bit |

The system reset must last at least three cycles of `i_td_clk27`.

## 4. The BT.656 stream

Each line has a four-byte reference prefix, `FF 00 00 XY`, at the start (SAV) and at the end (EAV) of the active video. The `XY` byte has the form $1\,F\,V\,H\,P_3\,P_2\,P_1\,P_0$.

| Bit | Name | Meaning |
| :--- | :--- | :--- |
| 6 | `F` | Field, 0 in the first and 1 in the second |
| 5 | `V` | 1 outside the active video (vertical blanking) |
| 4 | `H` | 1 at the EAV, 0 at the SAV |
| 3 to 0 | `P` | Protection, $P_3 = V \oplus H$, $P_2 = F \oplus H$, $P_1 = F \oplus V$ and $P_0 = F \oplus V \oplus H$ |

Between the SAV and the EAV of an active line the bytes follow the order Cb, Y, Cr, Y, with 1440 bytes per line for 720 pixels. Each group of four bytes yields two pixels that share the Cb and the Cr. The three bytes that precede the `XY` of an EAV are only recognized as a prefix at that point and are therefore removed from the pixel queue; no prefix byte becomes a pixel. In NTSC the frame has 525 lines of 1716 bytes, and each field has 240 active lines.

### 4.1. Sync events

| Event | Condition |
| :--- | :--- |
| Line start | SAV with $V = 0$ |
| Field start | Line start with the previous code at $V = 1$ |
| Field end | First code with $V = 1$ after active video |
| Sync error | Invalid protection, SAV inside a line, EAV outside a line or EAV in the middle of a Cb Y Cr Y group |

The video is taken as present while the last valid code is less than `present_cycles` cycles old.

## 5. Capturing a frame

Writing 1 to `START` requests the capture of one frame, provided no capture is in progress. The capture waits for the start of the first field requested, stores the active lines and ends at the end of the last field. The field is chosen in `FORMAT`.

| `FIELD` | Fields captured | Source line |
| :--- | :--- | :--- |
| 0 | Both, interlaced | Line $n$ of field $F$ is line $2n + F$ of the frame |
| 1 | The first only | Line $n$ of the field is line $n$ |
| 2 | The second only | Line $n$ of the field is line $n$ |

The capture is aborted, with no frame ready and the sync error raised, if the video stops being present or if a field arrives out of the expected order. Requesting a capture with no video present aborts at once.

### 5.1. Decimation

With the factors $x$ in columns and $y$ in lines, the source pixel at column $c$ and line $r$ goes to the memory only if $c$ and $r$ are multiples of $x$ and $y$, and its position in the memory is $(c / x,\ r / y)$. Decimation is point sampling, with no averaging. Pixels outside `src_width` by `src_height` or outside `fb_width` by `fb_height` are discarded.

### 5.2. Pixel format

| `PIXEL` | Format | Pixels per word |
| :--- | :--- | :--- |
| 0 | RGB565, red in bits 15:11, green in 10:5 and blue in 4:0 | 2, the even-indexed one in bits 15:0 |
| 1 | 8-bit luma Y | 4, the one of index $4k + n$ in byte $n$ |

The pixel of index $i$ is the one at line $\lfloor i / \text{fb\_width} \rfloor$ and column $i \bmod \text{fb\_width}$ of the memory. The conversion follows ITU-R BT.601 with luma from 16 to 235, in fixed point with 8 fractional bits, and saturates each channel to 0 to 255 before reducing it:

$$R = \frac{298\,(Y - 16) + 409\,(C_r - 128) + 128}{256}$$

$$G = \frac{298\,(Y - 16) - 100\,(C_b - 128) - 208\,(C_r - 128) + 128}{256}$$

$$B = \frac{298\,(Y - 16) + 516\,(C_b - 128) + 128}{256}$$

With $Y < 16$ the luma term is zero.

## 6. Register map

Accesses are 32 bits wide. The word address is the byte offset divided by 4.

| Word | Offset | Name | Access | Reset | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 0 | `0x00` | `CTRL` | R/W | 0 | Control |
| 1 | `0x04` | `STATUS` | R/W1C | 0 | Status |
| 2 | `0x08` | `FRAME_COUNT` | R | 0 | Complete frames captured since reset |
| 3 | `0x0C` | `DECIMATION` | R/W | `0x0101` | Decimation factors |
| 4 | `0x10` | `FORMAT` | R/W | 0 | Pixel format and field |
| 5 | `0x14` | `GEOMETRY` | R | generics | Width in bits 15:0 and height in 31:16 of the frame memory |
| 6 | `0x18` | `RD_ADDR` | R/W | 0 | Word read pointer of the frame memory |
| 7 | `0x1C` | `RD_DATA` | R | 0 | Word of the frame memory at the pointer, advancing the pointer |
| 8 | `0x20` | `SOURCE` | R | generics | `src_width` in bits 15:0 and `src_height` in 31:16 |

An address with no register reads zero and ignores writes. W1C is write 1 to clear.

### 6.1. `CTRL`

| Bit | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| 0 | `START` | W | Writing 1 starts the capture of one frame; ignored while a capture is in progress; reads 0. It also clears `READY` |
| 1 | `FRAME_IRQ` | R/W | Enables the frame ready interrupt |
| 2 | `ERROR_IRQ` | R/W | Enables the sync error interrupt |
| 3 | `DECODER_RUN` | R/W | 1 releases the decoder reset (`TD_RESET_N` high); 0 after reset |

Every write to `CTRL` stores bits 1 to 3 with the values written.

### 6.2. `STATUS`

| Bit | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| 0 | `BUSY` | R | Capture in progress, from an accepted `START` until the capture ends |
| 1 | `READY` | R/W1C | Complete frame in the memory; rises at the end of a complete capture and falls with `START` |
| 2 | `ERROR` | R/W1C | Sync error since it was cleared, from the receiver or an aborted capture |
| 3 | `PRESENT` | R | Valid timing codes arriving |

### 6.3. `DECIMATION`, `FORMAT` and memory read

| Register | Field | Bits | Description |
| :--- | :--- | :--- | :--- |
| `DECIMATION` | `X_DIV` | 7:0 | Factor in x from 1 to 255; writing 0 stores 1 |
| `DECIMATION` | `Y_DIV` | 15:8 | Factor in y from 1 to 255; writing 0 stores 1 |
| `FORMAT` | `PIXEL` | 0 | 0 RGB565, 1 luma |
| `FORMAT` | `FIELD` | 2:1 | 0 and 3 both fields, 1 the first only, 2 the second only |

`DECIMATION` and `FORMAT` accept writes only while no capture is in progress. The `RD_ADDR` pointer counts 32-bit words from 0 to $\lceil \text{fb\_width} \cdot \text{fb\_height} / 2 \rceil - 1$; writing a value outside the memory is ignored. Each read of `RD_DATA` returns the word at the pointer and advances it, wrapping to 0 after the last word. The word of a freshly written pointer is available on the next read. Reading the memory during a capture may return a mix of old and new pixels.

## 7. Interrupt

`o_irq` is a level, $\text{FRAME\_IRQ} \cdot \text{READY} + \text{ERROR\_IRQ} \cdot \text{ERROR}$. It falls when the software writes 1 to the `STATUS` bit that caused it (or, for `READY`, with a new `START`).

## 8. Clock domains

| Signal | From | To | Crossing |
| :--- | :--- | :--- | :--- |
| Reset | `i_clk` | `i_td_clk27` | Two-stage synchronizer |
| Capture request | `i_clk` | `i_td_clk27` | Toggle in a two-stage synchronizer |
| End of capture | `i_td_clk27` | `i_clk` | Toggle in a two-stage synchronizer |
| Receiver error | `i_td_clk27` | `i_clk` | Toggle in a two-stage synchronizer |
| Video present | `i_td_clk27` | `i_clk` | Level in a two-stage synchronizer |
| Capture result, factors, format and field | between the two | | Vectors held still at the moment the toggle reveals them |
| Pixels | `i_td_clk27` | `i_clk` | Two-port memory, one port on each clock |

The error and end-of-capture toggles are read in `i_clk`; `i_clk` must be faster than 13.5 MHz (half of `TD_CLK27`), because two timing codes are at least four `TD_CLK27` cycles apart and a toggle per error must not be lost. The platform constraints file must cut with `set_false_path` the path into the first stage of each synchronizer, the held vectors and the path between the two ports of the memory.

## 9. Memory

The frame memory has $\lceil \text{fb\_width} \cdot \text{fb\_height} / 2 \rceil$ 32-bit words in four byte lanes, so that Quartus infers memory blocks with byte enables. Each lane takes $\lceil \text{words} / 1024 \rceil$ blocks of 1024 8-bit words, and the whole memory takes four times that.

| Configuration | Words | Memory blocks |
| :--- | :--- | :--- |
| 160x120 (default) | 9600 | 40 |
| 180x120 | 10800 | 44 |
| 320x240 | 38400 | 152 |

The DE2-115 (Cyclone IV E) has 432 M9K blocks.

## 10. Software use

The example captures an RGB565 frame decimated by 4 in x and in y (180x120) and copies it to an array. The ADV7180 configuration over I2C comes before, with the platform's I2C peripheral, and is not part of this peripheral.

```c
#include <stdint.h>

#define TV_CTRL        0
#define TV_STATUS      1
#define TV_FRAME_COUNT 2
#define TV_DECIMATION  3
#define TV_FORMAT      4
#define TV_GEOMETRY    5
#define TV_RD_ADDR     6
#define TV_RD_DATA     7

#define CTRL_START       (1u << 0)
#define CTRL_DECODER_RUN (1u << 3)
#define STATUS_BUSY      (1u << 0)
#define STATUS_READY     (1u << 1)
#define STATUS_ERROR     (1u << 2)
#define STATUS_PRESENT   (1u << 3)

/* Captures an RGB565 frame of both fields, decimated by x_div and y_div, into out.
   Returns 0 on success and -1 if the capture failed. */
int tv_capture_frame(volatile uint32_t *tv, uint16_t *out, uint32_t x_div, uint32_t y_div)
{
    tv[TV_CTRL] = CTRL_DECODER_RUN;                  /* releases the ADV7180 reset */
    /* ... here the software programs the ADV7180 over I2C and waits for video ... */
    while ((tv[TV_STATUS] & STATUS_PRESENT) == 0) {
    }

    tv[TV_DECIMATION] = (y_div << 8) | x_div;
    tv[TV_FORMAT]     = 0;                           /* RGB565, both fields */
    tv[TV_STATUS]     = STATUS_READY | STATUS_ERROR; /* clears old flags */
    tv[TV_CTRL]       = CTRL_START | CTRL_DECODER_RUN;

    uint32_t status;
    do {
        status = tv[TV_STATUS];
    } while ((status & STATUS_BUSY) != 0);

    if ((status & STATUS_READY) == 0) {
        return -1;
    }

    uint32_t geometry = tv[TV_GEOMETRY];
    uint32_t pixels   = (geometry & 0xFFFFu) * (geometry >> 16);

    tv[TV_RD_ADDR] = 0;
    for (uint32_t i = 0; i < pixels; i += 2) {
        uint32_t word = tv[TV_RD_DATA];
        out[i]     = (uint16_t)(word & 0xFFFFu);
        if (i + 1 < pixels) {
            out[i + 1] = (uint16_t)(word >> 16);
        }
    }

    return 0;
}
```

With the interrupt, the software enables `FRAME_IRQ` in `CTRL`, returns after the `START` and, in the handler, reads `STATUS`, copies the frame and writes 1 to `READY` to lower `o_irq`. A capture takes up to one field of waiting plus one frame, about 50 ms in NTSC.

## 11. Verification

| Check | Coverage |
| :--- | :--- |
| Entity test `TV` | NTSC BT.656 stream generator of 720x480 interlaced, 525 lines of 1716 bytes. Reset values and geometry, capture of an RGB565 frame of both fields with 4x4 decimation and interrupt, of luma of the second field with 4x2 decimation, with factors 3 and 5 that clip columns beyond the memory, configuration rules during a capture, an injected protection error, a capture with no video and the read pointer. Every pixel written is compared with a model |
| Entity tests `TVReceiver` and `TVColor` | Receiver: pixels against the bytes sent, one field start and end, second field, a prefix that never becomes a pixel, invalid protection, a misaligned line, SAV without EAV and the loss of video presence. Color: conversion to RGB565 and luma against the model, with the extremes of Y, Cb and Cr and 3000 random pixels, and the packing by index |
| Entity tests `TVRegs` and `TVCapture` | Registers: reset, start and end by toggle, configuration locked during a capture, interrupt with the masks, receiver error and read pointer. Control: decimation in x and in y, interlaced fields and a single field, aborts for lack of video and for a field out of order, and a field end without a start |
| Formal proof `tv_regs` | The registers, the interrupt, the request toggle, the configuration lock, the frame ready, the counter, the error and the read pointer follow a reference model for any sequence of accesses and of events from the other domain; all nine injected defects are caught; cover of a complete and of an aborted end of capture |
| Formal proof `tv_capture` | Protocol of the capture of one frame in the three field modes: a single end pulse, a complete frame only after the fields requested, in order, pixels only during the capture and inside the memory, reset; three injected defects are caught; cover of a complete frame |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
