# I2S audio interface (`audio`)

## 1. What it is

The audio interface connects the core bus to an audio codec over I2S, such as the WM8731 of the DE2-115. It generates the codec master clock and the bit and channel clocks, serializes the playback samples, deserializes the recorded ones, keeps both in queues and can play a test square wave with no software. The codec itself (volumes, format, rate) is configured over I2C with the `i2c_master` peripheral and does not go through this interface.

| Item | Value |
| :--- | :--- |
| Format | I2S, left channel with `LRCK` at zero, data changing on the falling edge of `BCLK` and the most significant bit one `BCLK` cycle after the `LRCK` change |
| Word width | 16, 24 or 32 bits per channel (generic `word_bits` and the `WORD` field) |
| Mode | Master or slave for `BCLK` and `LRCK` (generic `master`); `AUD_XCK` is always generated |
| Default | 12.288 MHz on `AUD_XCK`, 3.072 MHz on `BCLK` and 48 kHz sampling, with a 50 MHz system clock |
| Queues | One for playback and one for recording, with depth set by generic (default 32 words) |
| Register block | 14 words, 4-bit `i_address` |
| Mapped access | 1 cycle, no bus wait |

## 2. Top-level ports and integration

| Port | Direction | Connection |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | System clock and synchronous active-high reset |
| `i_data_in`, `i_address` (4 bits), `i_write`, `i_read`, `o_data_out` | bus | 16-word slot on the interconnect |
| `o_irq` | output | Level interrupt source for the PLIC |
| `o_xck` | output | `AUD_XCK` pin (E1) |
| `i_bclk`, `o_bclk`, `o_bclk_oe` | input, output and enable | `AUD_BCLK` pin (F2) |
| `i_adclrck`, `o_adclrck`, `o_adclrck_oe` | input, output and enable | `AUD_ADCLRCK` pin (C2) |
| `i_daclrck`, `o_daclrck`, `o_daclrck_oe` | input, output and enable | `AUD_DACLRCK` pin (E3) |
| `i_adcdat` | input | `AUD_ADCDAT` pin (D2) |
| `o_dacdat` | output | `AUD_DACDAT` pin (D1) |

The three bidirectional pins follow the pattern of the other interfaces, where the tristate layer of the platform top drives the output when the enable is one. In master mode the three enables are one and the inputs are ignored. In slave mode they are zero, and `BCLK`, `ADCLRCK` and `DACLRCK` go through two-stage synchronizers, which requires a system clock of at least four times the `BCLK` frequency.

### 2.1. Generics

| Generic | Default | Meaning |
| :--- | :--- | :--- |
| `clk_freq` | 50 000 000 | System clock frequency in Hz |
| `xck_freq` | 12 288 000 | `AUD_XCK` frequency in Hz, at most `clk_freq / 2` |
| `sample_rate` | 48 000 | Sampling rate in Hz that sets the `BCLK` divider at reset |
| `slot_bits` | 32 | `BCLK` cycles per channel at reset, at least `word_bits` |
| `word_bits` | 24 | Word width at reset (16, 24 or 32) |
| `tx_fifo_depth`, `rx_fifo_depth` | 32 | Queue depth in words, from 2 to 65535 |
| `master` | true | Master mode for `BCLK` and `LRCK` |
| `has_tone` | true | Includes the tone generator |
| `tone_freq`, `tone_amp` | 1000 and 8192 | Tone frequency in Hz and 16-bit amplitude at reset |
| `autostart` | false | Reset with clocks, playback and tone on |

## 3. Clocks

The master clock is a square wave produced by a fractional accumulator. Every cycle the accumulator adds `XCK_STEP` and, on reaching `XCK_MOD`, subtracts `XCK_MOD` and flips `AUD_XCK`. With $step = 2 \cdot f_{xck}$ and $mod = f_{clk}$ the ratio is exact on average, and the output has at most one system clock period of jitter.

$$f_{xck} = \frac{XCK\_STEP}{XCK\_MOD} \cdot \frac{f_{clk}}{2}, \qquad f_{bclk} = \frac{f_{xck}}{BCLK\_DIV}, \qquad f_s = \frac{f_{bclk}}{2 \cdot SLOT\_BITS}$$

The reset values give 12.288 MHz, 3.072 MHz and 48 kHz. The other board rates come from reprogramming the registers, and register 8 of the codec must select the same ratio between `AUD_XCK` and the sampling rate.

| Sampling rate | `XCK_STEP` (50 MHz clock) | `BCLK_DIV` | `SLOT_BITS` |
| ---: | ---: | ---: | ---: |
| 48 kHz | 24 576 000 | 4 | 32 |
| 96 kHz | 24 576 000 | 2 | 32 |
| 32 kHz | 24 576 000 | 6 | 32 |
| 8 kHz | 24 576 000 | 24 | 32 |
| 44.1 kHz | 22 579 200 | 4 | 32 |

$XCK\_STEP \le XCK\_MOD$ must hold, and a zero `XCK_STEP` keeps the pin at zero. In master mode `LRCK` flips on the falling edge of `BCLK`, together with the data change, every `SLOT_BITS` `BCLK` cycles. Generation only runs with `CLK_EN` at one.

## 4. Registers

Addresses are word addresses. Every field not listed reads zero.

| Word | Name | Access | Reset | Description |
| ---: | :--- | :--- | :--- | :--- |
| 0 | `CONTROL` | R/W | 0 (see below) | Enables, described in the next table |
| 1 | `STATUS` | R/W1C | `TX_NOT_FULL` and `TX_EMPTY` | Queue state and error flags |
| 2 | `LEVELS` | R | 0 | Bits 15:0 playback queue level, bits 31:16 recording queue level |
| 3 | `TX_DATA` | W | n/a | Pushes a sample into the playback queue; a read returns zero |
| 4 | `RX_DATA` | R | n/a | Oldest sample of the recording queue, removed at the end of the read |
| 5 | `IRQ_LEVEL` | R/W | `0x0001_0000` | Bits 15:0 playback threshold, bits 31:16 recording threshold |
| 6 | `XCK_STEP` | R/W | $2 \cdot$ `xck_freq` | Accumulator step of the master clock |
| 7 | `XCK_MOD` | R/W | `clk_freq` | Accumulator modulus of the master clock |
| 8 | `BCLK_DIV` | R/W | $f_{xck} / f_{bclk}$ | Bits 15:0, master clock flips between `BCLK` flips |
| 9 | `SLOT_BITS` | R/W | `slot_bits` | Bits 15:0, `BCLK` cycles per channel |
| 10 | `TONE_HALF` | R/W | $f_s / (2 \cdot$ `tone_freq`$)$ | Bits 15:0, frames per tone half-cycle |
| 11 | `TONE_AMP` | R/W | `tone_amp` | Bits 15:0, tone amplitude on a 16-bit scale |
| 12 | `CONFIG` | R | n/a | Bits 15:0 playback depth, bits 31:16 recording depth |
| 13 | `CAPS` | R | n/a | Bit 0 `MASTER`, bit 1 `HAS_TONE` |

With `autostart` false, `CONTROL` clears every enable and the `WORD` field holds the code of `word_bits`. With `autostart` true, `TX_EN`, `CLK_EN` and `TONE_EN` are one.

| `CONTROL` bits | Name | Meaning |
| :--- | :--- | :--- |
| 0 | `TX_EN` | The serializer consumes frames from the queue (or the tone) |
| 1 | `RX_EN` | The deserializer stores frames in the recording queue |
| 2 | `TX_IRQ_EN` | Enables the playback queue interrupt |
| 3 | `RX_IRQ_EN` | Enables the recording queue interrupt |
| 4 | `ERR_IRQ_EN` | Enables the error interrupt |
| 5 | `CLK_EN` | Generates `AUD_XCK` and, in master mode, `BCLK` and `LRCK` |
| 6 | `TONE_EN` | Replaces the playback queue with the test tone (only with `has_tone`) |
| 9:8 | `WORD` | Word width, 0 for 16, 1 for 24, 2 or 3 for 32 bits |

| `STATUS` bits | Name | Meaning |
| :--- | :--- | :--- |
| 0 | `TX_NOT_FULL` | The playback queue accepts a word |
| 1 | `RX_NOT_EMPTY` | The recording queue holds a word |
| 2 | `TX_EMPTY` | The playback queue is empty |
| 3 | `RX_FULL` | The recording queue is full |
| 4 | `TX_UNDERFLOW` | A frame started without two words in the playback queue |
| 5 | `RX_OVERFLOW` | A received frame was dropped with the recording queue lacking room for two |
| 6 | `TX_DROPPED` | A write to `TX_DATA` was dropped with the queue full |

Bits 4 to 6 are persistent. Writing one to the bit itself clears it, and writing zero preserves it. A new event in the same cycle as a clear takes priority.

## 5. Sample format

The playback and recording queues hold the samples interleaved, left and right, one per 32-bit word.

| Direction | 32-bit word format |
| :--- | :--- |
| Playback | The `WORD` least significant bits form the two's complement sample; the bits above are ignored |
| Recording | The `WORD`-bit sample arrives sign-extended to 32 bits |

A playback frame is only consumed when the queue holds at least two words at the start of the left channel. With fewer, both channels output zero, `TX_UNDERFLOW` rises and the queue words stay, which keeps the left and right order. On recording, a frame is only accepted if the queue has room for both words; otherwise the whole frame is dropped and `RX_OVERFLOW` rises. In both directions the oldest words are preserved.

When `SLOT_BITS` is larger than the word width, the remaining bits of the channel are output as zero and ignored on input. When it is equal, the last sample bit is output together with the `LRCK` change, as the I2S format requires.

## 6. Test tone

With `TONE_EN` at one, the serializer stops reading the playback queue and sends on both channels a square wave of $+TONE\_AMP$ and $-TONE\_AMP$, flipping every `TONE_HALF` frames. The amplitude is on a 16-bit scale and takes the highest bits of the word, so the same value gives the same volume in 16, 24 or 32 bits.

$$f_{tone} = \frac{f_s}{2 \cdot TONE\_HALF}$$

With 48 kHz and `TONE_HALF` equal to 24 the tone is 1 kHz. With the `autostart` generic the tone leaves reset with no write at all, which proves the clock, serializer and pin path with no software.

## 7. Interrupt

The `o_irq` output is level and is the OR of three causes, each with its own enable, cleared at reset.

| Cause | Condition | Stops holding when |
| :--- | :--- | :--- |
| Playback (`TX_IRQ_EN`) | Playback queue level less than or equal to the `TX` threshold of `IRQ_LEVEL` | Software pushes samples above the threshold |
| Recording (`RX_IRQ_EN`) | Recording queue level greater than or equal to the `RX` threshold of `IRQ_LEVEL` | Software pops samples below the threshold |
| Error (`ERR_IRQ_EN`) | `TX_UNDERFLOW`, `RX_OVERFLOW` or `TX_DROPPED` set | Software clears the bits in `STATUS` |

## 8. Usage sequence

1. Configure the codec over I2C (section 9).
2. Write `CONTROL` with the wanted word width in `WORD` and no enables.
3. Reprogram `XCK_STEP`, `XCK_MOD`, `BCLK_DIV` and `SLOT_BITS` if the rate is not the reset one.
4. Preload the playback queue with `TX_DATA` until `TX_NOT_FULL` drops.
5. Write `CONTROL` with `CLK_EN`, `TX_EN` (and `RX_EN` to record).
6. Refill the queue by polling `STATUS` or by level interrupt, and read `RX_DATA` while `RX_NOT_EMPTY` holds.

## 9. C example

The example plays a 1 kHz tone in two ways, in hardware with the tone generator and in software by pushing the wave into the queue. The `i2c_write` function belongs to the `i2c_master` driver, and `AUDIO_BASE` is the peripheral base in the platform. The WM8731 is the I2S slave, so the format, width and rate are chosen by registers 7 and 8 of the codec, which have a 7-bit address and 9-bit data.

```c
#include <stdbool.h>
#include <stdint.h>

#define AUDIO_REG(n) (*(volatile uint32_t *)(AUDIO_BASE + 4u * (n)))

enum {
    AUDIO_CONTROL, AUDIO_STATUS, AUDIO_LEVELS, AUDIO_TX_DATA, AUDIO_RX_DATA, AUDIO_IRQ_LEVEL,
    AUDIO_XCK_STEP, AUDIO_XCK_MOD, AUDIO_BCLK_DIV, AUDIO_SLOT_BITS, AUDIO_TONE_HALF, AUDIO_TONE_AMP
};

#define TX_EN      (1u << 0)
#define CLK_EN     (1u << 5)
#define TONE_EN    (1u << 6)
#define WORD_16    (0u << 8)
#define TX_NOT_FULL (1u << 0)

extern void i2c_write(uint8_t device, uint8_t reg, uint16_t value);

#define WM8731 0x1Au

static void codec_setup(void)
{
    i2c_write(WM8731, 15, 0x000);  /* reset the codec */
    i2c_write(WM8731, 6, 0x000);   /* power every block */
    i2c_write(WM8731, 2, 0x079);   /* headphone volume */
    i2c_write(WM8731, 4, 0x010);   /* select the DAC */
    i2c_write(WM8731, 5, 0x000);   /* no digital mute */
    i2c_write(WM8731, 7, 0x002);   /* slave, I2S, 16 bits */
    i2c_write(WM8731, 8, 0x000);   /* 48 kHz with a 12.288 MHz master clock */
    i2c_write(WM8731, 9, 0x001);   /* activate the digital interface */
}

static void tone_in_hardware(void)
{
    AUDIO_REG(AUDIO_TONE_HALF) = 24;      /* 48 kHz / (2 * 24) = 1 kHz */
    AUDIO_REG(AUDIO_TONE_AMP) = 0x2000;
    AUDIO_REG(AUDIO_CONTROL) = WORD_16 | CLK_EN | TX_EN | TONE_EN;
}

static void tone_in_software(void)
{
    AUDIO_REG(AUDIO_CONTROL) = WORD_16 | CLK_EN | TX_EN;

    for (uint32_t frame = 0;; ++frame) {
        const int16_t sample = ((frame / 24u) & 1u) ? -0x2000 : 0x2000;

        while (!(AUDIO_REG(AUDIO_STATUS) & TX_NOT_FULL)) {
        }
        AUDIO_REG(AUDIO_TX_DATA) = (uint16_t)sample;  /* left */
        while (!(AUDIO_REG(AUDIO_STATUS) & TX_NOT_FULL)) {
        }
        AUDIO_REG(AUDIO_TX_DATA) = (uint16_t)sample;  /* right */
    }
}

int main(void)
{
    codec_setup();
    tone_in_hardware();
    /* tone_in_software() plays the same tone through the queue. */
    for (;;) {
    }
}
```

## 10. Verification

The entity tests use a codec model that rebuilds the samples the DAC receives and feeds the ADC, in master and slave modes and with tight and padded channels. They cover the reset state, the order and the 16, 24 and 32-bit widths on playback and on recording with sign extension, channel alignment after an underflow, the drop with a full queue, the threshold and error interrupts, the 48 kHz and 44.1 kHz clock rates and the tone, including `autostart`. The formal proofs cover the master clock generator, the bit and channel dividers and the contract of the registers, queues and interrupt, with mutants.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
