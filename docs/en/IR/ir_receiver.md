# Infrared receiver with NEC decoder

🌐 [Português](../../pt-br/IR/ir_receiver.md) · [English](../../en/IR/ir_receiver.md)

## 1. Reference

The DE2-115 has an infrared receiver module (IRM-V538N7/TR1) that delivers the demodulated signal. The module accepts only a 38 kHz carrier, with a maximum rate of about 4 kbit/s, and the remote control shipped with the board uses the uPD6121G encoder, which generates the NEC protocol. The module output reaches the `IRDA_RXD` pin (`PIN_Y15`, 3.3 V).

This peripheral measures every pulse and every space of the line in clock cycles, recognizes NEC frames (including the repeat code and the 16-bit extended address), stores the frames in a FIFO and leaves the last raw measure available to software, for other protocols.

## 2. Parameters

| Generic | Default | Meaning |
| :--- | :--- | :--- |
| `clk_freq_hz` | 50000000 | Clock frequency in Hz, below 238 MHz. Every NEC time derives from it |
| `tolerance_percent` | 25 | Tolerance of each width around its nominal value, in percent, from 0 to 30 |
| `glitch_us` | 20 | Minimum time, in microseconds, that the line must stay stable for a change to count |
| `timeout_us` | 12000 | Maximum time, in microseconds, of one level inside a frame, longer than the 9 ms leading pulse |
| `fifo_depth` | 8 | Number of frames in the FIFO, from 1 to 255 |
| `raw_enable` | `true` | With `false`, the raw widths are not stored and both registers read zero |
| `active_low` | `true` | Pulse at low level, as the board module; with `false` the pulse is the high level |

## 3. Interface

| Port | Direction | Function |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | Clock and synchronous reset, active at 1 |
| `i_data_in`, `i_address` | input | Write data (`word_t`) and 3-bit word address |
| `i_write`, `i_read` | input | Write and read strobes |
| `o_data_out` | output | Read data, combinational on the address and sampled before the edge of the read |
| `o_irq` | output | Level interrupt, active at 1 |
| `i_irda_rxd` | input | Receiver pin, asynchronous; goes through a two-stage synchronizer |

## 4. NEC decoding

### 4.1. Frame

The time unit is $T = 562.5\ \mu s$. A frame is the sequence of pulses and spaces in the table, and the least significant bit of each byte is sent first.

| Element | Pulse | Space |
| :--- | :--- | :--- |
| Frame start | $16T$ (9 ms) | $8T$ (4.5 ms) |
| Bit 0 | $T$ | $T$ |
| Bit 1 | $T$ | $3T$ |
| Final pulse | $T$ | |
| Repeat | $16T$, then $T$ at the end | $4T$ (2.25 ms) |

The 32 bits of the frame form four bytes: address, inverted address (or high address byte, in extended NEC), command and inverted command.

### 4.2. Tolerance

A measured width $w$ is valid for $n$ units when

$$nT_c\left(1 - \frac{p}{100}\right) \le w \le nT_c\left(1 + \frac{p}{100}\right)$$

with $p$ equal to `tolerance_percent` and $T_c = \lfloor f_{clk} / 16000 \rfloor \cdot 9$ cycles, the unit $T$ converted to the clock.

### 4.3. Validation

| Situation | Result |
| :--- | :--- |
| Command and inverted command are complementary | Frame accepted; otherwise malformed frame |
| Inverted address is the complement of the address | 8-bit address (`extended` at 0, high byte zero) |
| Inverted address is not the complement, bit `EXT_EN` at 1 | 16-bit address (`extended` at 1) |
| Inverted address is not the complement, bit `EXT_EN` at 0 | Malformed frame |
| Repeat after a valid frame | Frame with the repeat flag and the address and command of the previous frame |
| Repeat with no previous frame | Malformed frame |

A malformed frame sets `FRAME_ERR` and is discarded. An error exists only after a valid leading pulse, so noise pulses that do not match the frame start are ignored without error. After an error the decoder returns to idle, and a pulse that already matches the frame start begins the next frame. A level that lasts longer than `timeout_us` inside a frame is also a malformed frame.

### 4.4. Noise filter

The synchronized line changes level only after staying `glitch_us` microseconds stable at the new level, and the width of each level is counted from that change. Noise pulses shorter than the filter do not appear in the measures.

## 5. Register map

Accesses are 32 bits wide, and the address is a word address. An address outside the map reads zero and ignores writes.

| Address | Register | Access | Reset | Description |
| :--- | :--- | :--- | :--- | :--- |
| 0 | `CTRL` | R/W | `0x08` | Control |
| 1 | `STATUS` | R/W (writing 1 clears) | 0 | Status |
| 2 | `DATA` | R | 0 | Oldest frame of the FIFO; reading it removes it |
| 3 | `RAW_MARK` | R | 0 | Width in cycles of the last pulse |
| 4 | `RAW_SPACE` | R | 0 | Width in cycles of the last space |

### 5.1. `CTRL`

| Bit | Name | Description |
| :--- | :--- | :--- |
| 0 | `EN` | Enables the receiver; at 0, the meter and the decoder stay stopped and the FIFO is kept |
| 1 | `FRAME_IE` | Interrupt while the FIFO is not empty |
| 2 | `ERR_IE` | Interrupt while `FRAME_ERR` or `OVERFLOW` is 1 |
| 3 | `EXT_EN` | Accepts the 16-bit extended address |
| 4 | `RAW_IE` | Interrupt while `RAW_NEW` is 1 |
| 5 | `FLUSH` | Writing 1 empties the FIFO; always reads 0 |

### 5.2. `STATUS`

| Bit | Name | Description |
| :--- | :--- | :--- |
| 0 | `NOT_EMPTY` | The FIFO holds at least one frame |
| 1 | `FULL` | The FIFO is full |
| 2 | `FRAME_ERR` | Malformed frame discarded; stays at 1 until 1 is written to the bit |
| 3 | `OVERFLOW` | A valid frame arrived with the FIFO full and was lost; stays at 1 until 1 is written to the bit |
| 4 | `LINE` | Filtered line level, 1 during a pulse |
| 5 | `RAW_NEW` | A new raw measure arrived; stays at 1 until 1 is written to the bit |
| 15:8 | `LEVEL` | Number of frames in the FIFO |

### 5.3. `DATA`

| Bits | Field | Description |
| :--- | :--- | :--- |
| 15:0 | `address` | Address; in 8-bit NEC only the low 8 bits count |
| 23:16 | `command` | Command |
| 24 | `repeat` | 1 when the frame is a repeat of the previous one |
| 25 | `extended` | 1 when the frame used the 16-bit address |

With the FIFO empty the read returns zero and removes nothing.

## 6. Raw measure

At the end of every pulse and every space, the meter stores the width in clock cycles in `RAW_MARK` or `RAW_SPACE` and sets `RAW_NEW`. Software that wants to handle another protocol waits for `RAW_NEW`, reads both registers, writes 1 to `RAW_NEW` and converts the cycles to time with the clock frequency. Both registers change at every measure, so software that needs both values of one pair must read them right after `RAW_NEW` rises, before the next measure.

## 7. Interrupt

$$o\_irq = (FRAME\_IE \wedge NOT\_EMPTY) \vee (ERR\_IE \wedge (FRAME\_ERR \vee OVERFLOW)) \vee (RAW\_IE \wedge RAW\_NEW)$$

The output is a level. The first term drops when software removes the last frame, and the other two drop when software writes 1 to the matching bit of `STATUS`.

## 8. C example

The program turns the receiver on with the extended address and prints every frame received. The window base comes from the header generated from `platform.yaml`.

```c
#include <stdint.h>
#include <stdio.h>

enum { IR_CTRL, IR_STATUS, IR_DATA, IR_RAW_MARK, IR_RAW_SPACE };

enum : uint32_t {
    CTRL_EN = 1u << 0,
    CTRL_EXT_EN = 1u << 3,
    STAT_NOT_EMPTY = 1u << 0,
    STAT_FRAME_ERR = 1u << 2,
    STAT_OVERFLOW = 1u << 3,
    FRAME_REPEAT = 1u << 24,
    FRAME_EXT = 1u << 25,
};

static volatile uint32_t *const ir = (volatile uint32_t *)IR_WINDOW_BASE;

int main(void) {
    ir[IR_CTRL] = CTRL_EN | CTRL_EXT_EN;

    for (;;) {
        uint32_t status = ir[IR_STATUS];

        if (status & (STAT_FRAME_ERR | STAT_OVERFLOW)) {
            ir[IR_STATUS] = status & (STAT_FRAME_ERR | STAT_OVERFLOW);
            puts("frame lost or malformed");
        }

        if (status & STAT_NOT_EMPTY) {
            uint32_t frame = ir[IR_DATA];
            printf("address=0x%04x command=0x%02x%s%s\n",
                   (unsigned)(frame & 0xFFFFu), (unsigned)((frame >> 16) & 0xFFu),
                   (frame & FRAME_EXT) ? " extended" : "",
                   (frame & FRAME_REPEAT) ? " repeat" : "");
        }
    }
}
```

## 9. Pin

| Signal | DE2-115 pin | I/O standard | Description |
| :--- | :--- | :--- | :--- |
| `IRDA_RXD` | `PIN_Y15` | 3.3 V | Demodulated output of the infrared receiver, wired to `i_irda_rxd` |

## 10. Verification

The entity tests cover the FIFO, the meter, the decoder and the registers, and the test of the complete block uses a NEC frame generator that includes the standard and extended frames, repeats, widths with 12 % variation, noise pulses inside and outside a frame, truncated frames, a wrong complement, a full FIFO, flush, interrupt masks and the raw measure. The formal proof covers the FIFO and the registers (`ir_fifo_props.sv` and `ir_regs_props.sv`), with mutants and the cover check.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
