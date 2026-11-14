# HDMI audio output

🌐 [Português](../../pt-br/HDMI/hdmi_audio.md) · [English](../../en/HDMI/hdmi_audio.md)

## 1. Reference

The peripheral delivers stereo digital audio to the HDMI transmitter of a board over the I2S bus. The transmitter is the Analog Devices ADV7513, the same one as the HDMI video (`docs/en/HDMI/hdmi_tx.md`). The DE10-Nano manual (section 3.6.5 and section 5.3) confirms what this peripheral uses of the chip and what it leaves to software.

| Fact | Source |
| :--- | :--- |
| The four audio signals reach the FPGA on the pins of table 1.1, all at 3.3 V | DE10-Nano manual, Table 3-13 |
| The chip accepts 2 to 8 channels of I2S audio, at sampling rates up to 192 kHz | DE10-Nano manual, section 5.3 |
| The chip accepts standard I2S, left-justified and right-justified audio | DE10-Nano manual, section 5.3 |
| The audio frequency is in register `0x15` of the chip and the format in register `0xAF`, both written over I2C | DE10-Nano manual, section 5.3 |
| The Terasic example plays a sine signal at 48 kHz, 16 bits per channel, in standard I2S | DE10-Nano manual, section 5.3, Figure 5-6 |

The manual gives neither the values of the audio registers, nor the ratio between the master clock and the channel clock that the chip expects, nor the audio clock regeneration parameters (`N` and `CTS`). They are in the programming guide of the manufacturer, which is not part of the board manuals. For this reason the peripheral carries no ADV7513 register value, and the MCLK/LRCLK ratio is a generic that the platform chooses.

Not confirmed: the MCLK/LRCLK ratio that the ADV7513 requires, the values of the audio registers (rate, format, `N`, `CTS`, channel selection), and whether the chip tolerates the jitter of one system clock cycle on the MCLK of section 4.2. The ratios 128 and 256 times the sampling rate are the ones the peripheral offers.

### 1.1. Pins of the DE10-Nano manual

| Board signal | FPGA pin | Function in the chip | Peripheral port |
| :--- | :--- | :--- | :--- |
| `HDMI_MCLK` | PIN_U11 | Audio reference clock | `o_mclk` |
| `HDMI_SCLK` | PIN_T12 | I2S clock (bit clock) | `o_sclk` |
| `HDMI_LRCLK` | PIN_T11 | Left and right channel select | `o_lrclk` |
| `HDMI_I2S0` | PIN_T13 | I2S channel 0 data | `o_i2s0` |

## 2. What it is

The peripheral is a thin wrapper over the I2S audio peripheral (`docs/en/audio/audio.md`), used in master mode and for playback only. The wrapper computes the generics of the audio peripheral from the sampling rate and the MCLK/LRCLK ratio, connects the four outputs to the transmitter signals and fixes what does not exist in this direction, which is the audio input and the clock input pins. No logic is copied.

| Block | Function |
| :--- | :--- |
| `audio_xck_gen` | Generates the MCLK with a fractional phase accumulator from the system clock |
| `audio_frame_clocks` | Derives the SCLK and the LRCLK from the MCLK flips |
| `audio_i2s_tx` | Serializes one word per channel in the I2S format |
| `audio_tone` | Generates the hardware test square wave |
| `uart_fifo` | Playback sample queue, left and right interleaved |
| `audio` | Registers, queues and interrupt of the audio peripheral |
| `hdmi_audio` | Wrapper that chooses the generics and delivers the four pins of the transmitter |

The record queue and the deserializer of the audio peripheral stay unused, with the minimum depth and the input fixed at zero. Writing the `RX_EN` bit has no useful effect.

### 2.1. Generics

| Generic | Default | Meaning |
| :--- | :--- | :--- |
| `clk_freq` | 100000000 | System clock frequency in Hz, at least twice the MCLK frequency |
| `sample_rate` | 48000 | Sampling rate at reset in Hz: 32000, 44100 or 48000 |
| `mclk_ratio` | 256 | MCLK/LRCLK ratio at reset: 128 or 256 |
| `word_bits` | 24 | Word width at reset: 16 or 24 bits |
| `tx_fifo_depth` | 32 | Playback queue depth in words, at least 2 |
| `has_tone` | true | Includes the test tone generator |
| `tone_freq` | 1000 | Tone frequency at reset in Hz |
| `tone_amp` | 8192 | Tone amplitude at reset on a 16-bit scale |
| `autostart` | false | The reset already turns on the clocks, the playback and the tone, to play without software |

A value outside the lists above stops the elaboration with an error message.

## 3. Interface

| Port | Direction | Function |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | System clock and synchronous reset, active at 1 |
| `i_write`, `i_read` | input | Write and read pulses of the processor |
| `i_address` | input | Register word address, 4 bits |
| `i_data_in` | input | 32-bit write data |
| `o_data_out` | output | Read data, combinational on the address |
| `o_irq` | output | Level interrupt (queue thresholds and errors) |
| `o_mclk` | output | Master clock, for the `HDMI_MCLK` pin |
| `o_sclk` | output | Bit clock, for the `HDMI_SCLK` pin |
| `o_lrclk` | output | Channel clock, 0 in the left channel, for the `HDMI_LRCLK` pin |
| `o_i2s0` | output | Serial data, for the `HDMI_I2S0` pin |

The four pins are plain 3.3 V outputs, with no output enable and no vendor buffer.

## 4. Timing

### 4.1. Relations between the clocks

The slot of each channel has 32 SCLK cycles, and the 16-bit or 24-bit word goes out left-aligned, with zeros in the rest of the slot. With $f_s$ the sampling rate and $R$ the MCLK/LRCLK ratio,

$$f_{LRCLK} = f_s \qquad f_{SCLK} = 64 \, f_s \qquad f_{MCLK} = R \, f_s \qquad \frac{f_{MCLK}}{f_{SCLK}} = \frac{R}{64}$$

The SCLK flips every $R/64$ MCLK periods, which gives the divisor 2 for $R = 128$ and 4 for $R = 256$. The LRCLK flips every $R/2$ MCLK periods, and each half cycle is one channel.

| Rate $f_s$ | MCLK with $R = 128$ | MCLK with $R = 256$ | SCLK |
| :--- | :--- | :--- | :--- |
| 32 kHz | 4.096 MHz | 8.192 MHz | 2.048 MHz |
| 44.1 kHz | 5.6448 MHz | 11.2896 MHz | 2.8224 MHz |
| 48 kHz | 6.144 MHz | 12.288 MHz | 3.072 MHz |

The format is standard I2S: the LRCLK is 0 in the left channel, the most significant bit goes out one SCLK cycle after the LRCLK change and the data changes on the SCLK fall, so the receiver samples it stable on the rise.

### 4.2. MCLK generation

The MCLK comes from the system clock through a phase accumulator with step $2 f_{MCLK}$ and modulus $f_{clk}$. The mean frequency is exact, and each MCLK edge is displaced by at most one system clock period from the ideal instant. When the system clock is an even multiple of the MCLK there is no jitter. The condition is

$$f_{clk} \ge 2 \, f_{MCLK}$$

With a 100 MHz system clock and $R = 256$, the MCLK jitter is up to 10 ns. The SCLK and the LRCLK are counted on the MCLK flips and inherit the same jitter, with no accumulated error. The LRCLK measured over many frames has exactly the rate $f_s$, and a single half cycle lasts one cycle more or less than the mean.

## 5. Registers

The map is that of the audio peripheral, in 4-bit word addresses (`docs/en/audio/audio.md`, section 4). The registers used in playback, with the reset values that the wrapper computes, are:

| Word | Name | Reset value | Use |
| :--- | :--- | :--- | :--- |
| 0 | `CONTROL` | 0, or on with `autostart` | `TX_EN` (bit 0), `CLK_EN` (bit 5), `TONE_EN` (bit 6), `WORD` (bits 9:8, 0 = 16 and 1 = 24 bits) |
| 1 | `STATUS` | `TX_NOT_FULL` and `TX_EMPTY` | Playback queue, underflow and dropped write |
| 2 | `LEVELS` | 0 | Playback queue level in bits 15:0 |
| 3 | `TX_DATA` | | Pushes one sample, left and right alternating, in the low `word_bits` bits |
| 5 | `IRQ_LEVEL` | 0 | Playback queue interrupt threshold, in bits 15:0 |
| 6 | `XCK_STEP` | $2 \cdot R \cdot f_s$ | Step of the MCLK accumulator |
| 7 | `XCK_MOD` | `clk_freq` | Modulus of the MCLK accumulator |
| 8 | `BCLK_DIV` | $R / 64$ | MCLK flips per SCLK flip |
| 9 | `SLOT_BITS` | 32 | SCLK cycles per channel |
| 10 | `TONE_HALF` | $f_s / (2 \cdot tone\_freq)$ | Frames per tone half cycle |
| 11 | `TONE_AMP` | `tone_amp` | Tone amplitude |
| 12 | `CONFIG` | | Playback queue depth in bits 15:0 |
| 13 | `CAPS` | | Bit 0 at 1 (master mode) and bit 1 with the tone present |

### 5.1. Changing the rate at run time

The rate and the MCLK/LRCLK ratio can change by software, with `CLK_EN` at 0, by writing `XCK_STEP` with $2 \cdot R \cdot f_s$ and `BCLK_DIV` with $R / 64$, and turning `CLK_EN` on again. The condition $f_{clk} \ge 2 f_{MCLK}$ holds for any choice, and `SLOT_BITS` must stay at 32.

## 6. Transmitter configuration

The peripheral does not write to the ADV7513. The software, with the `i2c_master`, or the initialization sequencer of the `hdmi_tx`, with the audio table, writes the rate, the I2S format and the audio selection to the registers of the chip.

| Item | Status |
| :--- | :--- |
| Registers `0x15` (audio frequency) and `0xAF` (format) | They exist, per the board manual; the values are not confirmed |
| Other audio registers, `N` and `CTS` | Not confirmed; they are in the programming guide of the manufacturer |
| Sequencer audio table (`audio_init_table` of the `hdmi_tx`) | Empty by default, with no register value |

The `audio_init_table` generic of the `hdmi_tx` takes the audio table in the same format as the `init_table`, four hexadecimal digits per entry, register and then value. The sequencer writes the entries of the `init_table` and then those of the `audio_init_table`, and the two together add up to at most 255 entries. With the table empty, nothing is written for the audio. A platform that has the values of the manufacturer guide puts them in this generic, and the counting registers of the sequencer (`docs/en/HDMI/hdmi_tx.md`, section 7.3) count the entries of both.

## 7. Limits

| Limit | Detail |
| :--- | :--- |
| Two channels | The ADV7513 accepts 2 to 8 channels, but the peripheral generates only I2S channel 0, stereo; Table 3-13 of the manual lists only `HDMI_I2S0` |
| Rates | 32, 44.1 and 48 kHz at reset; other rates need the register adjustment of section 5.1 |
| Word | 16 and 24 bits; the 32-bit word of the audio peripheral is not accepted at reset |
| Format | Standard I2S; the left-justified and right-justified formats are not generated |
| Record | Does not exist; the transmitter only receives audio |

## 8. Wiring in the board top

1. `o_mclk`, `o_sclk`, `o_lrclk` and `o_i2s0` go to the pins `HDMI_MCLK`, `HDMI_SCLK`, `HDMI_LRCLK` and `HDMI_I2S0`, all at 3.3 V.
2. No PLL is needed: the system clock must be at least twice the MCLK frequency.
3. The .sdc declares the four outputs as system clock outputs, with no phase relation to the pixel clock.
4. The transmitter is configured through the I2C of the `hdmi_tx`, or through the `i2c_master` when the `hdmi_tx` has no sequencer.

## 9. C example

The program waits for the `hdmi_tx` sequencer to finish the initialization of the chip, turns on the master clock and the playback and plays a 1 kHz square wave at 48 kHz, with a 24-bit word and the same sample in both channels. The bases are defined by the platform, and the values of the audio registers of the chip are in the audio table of the platform.

```c
#include <stdint.h>

/* Peripheral bases, defined by the platform. */
#define HDMI_BASE        0x40000000u
#define HDMI_AUDIO_BASE  0x40010000u
#define HDMI_REG(word)   (*(volatile uint32_t *)(HDMI_BASE + 4u * (word)))
#define AUDIO_REG(word)  (*(volatile uint32_t *)(HDMI_AUDIO_BASE + 4u * (word)))

enum { HDMI_STATUS = 9u };
enum { STATUS_DONE = 1u << 2, STATUS_INIT = 1u << 4 };

enum { REG_CONTROL = 0u, REG_STATUS = 1u, REG_TX_DATA = 3u };
enum { CTRL_TX_EN = 1u << 0, CTRL_CLK_EN = 1u << 5, CTRL_WORD_24 = 1u << 8 };
enum { AUDIO_TX_NOT_FULL = 1u << 0 };

enum {
    SAMPLE_RATE = 48000,
    TONE_HZ = 1000,
    HALF_PERIOD = SAMPLE_RATE / (2 * TONE_HZ),
    AMPLITUDE = 0x2000,
};

static void push_sample(int32_t sample)
{
    while (!(AUDIO_REG(REG_STATUS) & AUDIO_TX_NOT_FULL)) {
    }
    AUDIO_REG(REG_TX_DATA) = (uint32_t)sample & 0xFFFFFFu;
}

int main(void)
{
    /* With the sequencer, wait for the table to reach the transmitter. */
    if (HDMI_REG(HDMI_STATUS) & STATUS_INIT) {
        while (!(HDMI_REG(HDMI_STATUS) & STATUS_DONE)) {
        }
    }

    /* Fill the queue before turning the playback on, to avoid underflow. */
    int32_t level = AMPLITUDE << 8;
    uint32_t frames = 0;
    for (uint32_t i = 0; i < 8; i++) {
        push_sample(level);
        push_sample(level);
    }
    AUDIO_REG(REG_CONTROL) = CTRL_CLK_EN | CTRL_TX_EN | CTRL_WORD_24;

    for (;;) {
        if (++frames == HALF_PERIOD) {
            frames = 0;
            level = -level;
        }
        push_sample(level);
        push_sample(level);
    }
}
```

The `TONE_EN` bit of the control register (bit 6) swaps the queue for the hardware tone and removes the sample loop, with `TONE_HALF` and `TONE_AMP` choosing the frequency and the amplitude.

## 10. Verification

| Verification | Coverage |
| :--- | :--- |
| Entity tests `HdmiAudio48k`, `HdmiAudio44k1` and `HdmiAudio32k` | Reset registers of each rate; exact count of MCLK and SCLK rises per channel and mean channel duration against the rate, measured on the outputs only; reconstruction, by an I2S receiver model, of the stereo samples written to the queue, with 16 and 24 bits and zeroed padding; rate change through registers |
| Entity test `HdmiAudioTone` | 1 kHz tone, at 44.1 kHz with 24 bits, with no bus write |
| Entity tests `HdmiInitSeqAudio`, `HdmiInitSeqAudioOnly` and `HdmiTxInitAudio` | The audio table goes out after the general table, or alone, with the I2C slave model of the ADV7513, and the counters add up both |
| Formal proofs `hdmiaud128_*`, `hdmiaud256_*` and `hdmiseq_audio_*` | Exact count, in cycles, of MCLK, SCLK and LRCLK at the ratios 128 and 256, the data changing only after the SCLK fall, and the order of the two sequencer tables, with mutants |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
