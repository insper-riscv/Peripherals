# HDMI Video Output

🌐 [Português](../../pt-br/HDMI/hdmi_tx.md) · [English](../../en/HDMI/hdmi_tx.md)

## 1. Reference

The peripheral delivers parallel digital video to the HDMI transmitter of a board. The transmitter is the Analog Devices ADV7513, which takes 24-bit RGB 4:4:4 pixels with the DE (data enable), HS and VS signals, does the TMDS encoding and serves video modes up to 1080p with a pixel clock of up to 165 MHz. The DE10-Nano manual describes the pixel bus as R[7:0] on bits 23:16, G[7:0] on bits 15:8 and B[7:0] on bits 7:0, and the chip is configured through an I2C interface.

The peripheral knows nothing about the board. The video mode, the pixel format and the initialization table of the chip arrive through generics, and the pixel clock comes from a PLL of the board top level.

### 1.1. Pins from the DE10-Nano manual

The signals below are the ones the board manual (Table 3-13) connects to the transmitter, all at 3.3 V. The board top level wires them to the peripheral ports.

| Board signal | FPGA pin | Peripheral port |
| :--- | :--- | :--- |
| `HDMI_TX_D0` to `HDMI_TX_D7` | AD12, AE12, W8, Y8, AD11, AD10, AE11, Y5 | `o_tx_d(0)` to `o_tx_d(7)`, blue channel |
| `HDMI_TX_D8` to `HDMI_TX_D15` | AF10, Y4, AE9, AB4, AE7, AF6, AF8, AF5 | `o_tx_d(8)` to `o_tx_d(15)`, green channel |
| `HDMI_TX_D16` to `HDMI_TX_D23` | AE4, AH2, AH4, AH5, AH6, AG6, AF9, AE8 | `o_tx_d(16)` to `o_tx_d(23)`, red channel |
| `HDMI_TX_CLK` | AG5 | `o_tx_clk` |
| `HDMI_TX_DE` | AD19 | `o_tx_de` |
| `HDMI_TX_HS` | T8 | `o_tx_hs` |
| `HDMI_TX_VS` | V13 | `o_tx_vs` |
| `HDMI_TX_INT` | AF11 | `i_tx_int` |
| `I2C_SCL` | U10 | `o_i2c_scl_out` and `o_i2c_scl_oe` |
| `I2C_SDA` | AA4 | `i_i2c_sda`, `o_i2c_sda_out` and `o_i2c_sda_oe` |

The audio pins of the transmitter (`HDMI_I2S0`, `HDMI_MCLK`, `HDMI_LRCLK` and `HDMI_SCLK`) are not used, because the peripheral does not carry HDMI audio.

## 2. What it is

The processor writes pixels into a framebuffer, and an independent scan-out reads them and sends them to the transmitter. The peripheral is a thin wrapper over the blocks of the video peripheral (`docs/en/video/video.md`) and adds what is specific to HDMI.

| Block | Domain | Function |
| :--- | :--- | :--- |
| `video_timing` | pixel | Column and line counters, syncs with polarity, visible area and framebuffer coordinates |
| `video_dpram` | system and pixel | Dual-port memory with independent clocks, one for the framebuffer and one for the palette |
| `video_regs` | system | Control register, frame status, geometry and format, framebuffer window and palette |
| `hdmi_scanout` | pixel | Read address, pixel pick in the word, palette or expansion of RGB565 to 24 bits |
| `hdmi_out` | pixel | Output register of the RGB bus, DE, HS and VS |
| `hdmi_regs` | system | HDMI registers (mode, status, interrupts, initialization restart) |
| `hdmi_init_seq` | system | Walks the table of register-value pairs and asks for one I2C write per pair |
| `hdmi_i2c_writer` | system | Write-only I2C master at 100 kHz, open drain |
| `hdmi_tx` | both | Structural top level, only instantiates and connects the blocks |

Each framebuffer pixel covers `scale` x `scale` screen pixels, and the image is centered in the visible area, with black bars over what is left of the frame. The framebuffer lives in a dual-port memory, written on the system clock and read on the pixel clock.

The timing, the dual-port memory and the framebuffer registers are those of the generic video peripheral with timing by generics, with no copy.

### 2.1. Generics

| Generic | Default | Meaning |
| :--- | :--- | :--- |
| `clk_freq` | 100000000 | System clock frequency in Hz, the base of the I2C SCL |
| `fb_width`, `fb_height` | 320, 180 | Framebuffer size; a row must fill a whole number of 32-bit words |
| `pixel_format` | `"indexed"` | `"indexed"` (8 bits with a 24-bit palette) or `"direct"` (16-bit RGB565) |
| `scale` | 4 | Magnification in x and in y; the magnified image must fit in the visible area |
| `addr_width` | 16 | Width of the window word address, at least 11 and larger than the framebuffer address |
| `h_visible`, `v_visible` | 1280, 720 | Visible pixels per line and visible lines per frame |
| `h_front_porch`, `v_front_porch` | 110, 5 | Front porches |
| `h_sync`, `v_sync` | 40, 5 | Sync pulse width in pixels and in lines |
| `h_back_porch`, `v_back_porch` | 220, 20 | Back porches |
| `h_sync_positive`, `v_sync_positive` | true, true | Pulse polarity, true for a high level during the pulse |
| `mode_id` | 4 | CEA-861 mode number (VIC), or 0 for a custom mode; informational only |
| `pixel_clock_khz` | 74250 | Pixel clock of the mode in kHz; informational only, the real clock comes from the PLL |
| `init_enable` | false | Includes the initialization sequencer of the transmitter |
| `init_auto_start` | true | The sequence starts by itself after reset |
| `init_table` | `""` | Initialization table, four hexadecimal digits per entry (section 7) |
| `i2c_dev_addr` | `0111001` | 7-bit address of the transmitter on the I2C bus |
| `i2c_freq` | 100000 | SCL frequency in Hz |
| `int_active_low` | true | The interrupt pin of the transmitter is active low |

## 3. Interface

| Port | Direction | Function |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | System clock and synchronous reset, active at 1 |
| `i_pixel_clk` | input | Pixel clock, asynchronous to `i_clk` |
| `i_data_in`, `i_address` | input | 32-bit write data and word address of `addr_width` bits |
| `i_byteena` | input | Byte enables of the write, one bit per byte |
| `i_write` | input | Write pulse from the processor |
| `o_data_out` | output | Read data, combinational on the address |
| `o_irq` | output | Level interrupt (section 8) |
| `o_tx_d` | output | 24-bit RGB video bus, red on 23:16 |
| `o_tx_clk` | output | `i_pixel_clk` itself, for the `HDMI_TX_CLK` pin |
| `o_tx_de`, `o_tx_hs`, `o_tx_vs` | output | Data enable and syncs, with the polarity of the mode |
| `i_tx_int` | input | Interrupt pin of the transmitter, asynchronous |
| `i_i2c_sda` | input | Level of the SDA line read from the pin, asynchronous |
| `o_i2c_sda_out`, `o_i2c_sda_oe` | output | Value (always 0) and output enable of SDA; enabled pulls the line low |
| `o_i2c_scl_out`, `o_i2c_scl_oe` | output | Value (always 0) and output enable of SCL |

The peripheral does not instantiate vendor buffers. The tristate layer of the board top level puts each I2C pin in high impedance when the enable is 0, and the pull-up resistor of the board takes the line to 1. A read has no side effect, so there is no read pulse. The system reset must last at least three cycles of `i_pixel_clk`, because it reaches the pixel domain through a two-stage synchronizer.

## 4. Address map

Accesses are 32 bits wide, and the addresses below are word addresses. The most significant bit of `i_address` separates the framebuffer window from the register space.

| Word address | Content | Access |
| :--- | :--- | :--- |
| 0 | Control, bit 0 turns the framebuffer display on (reset 0) | R/W |
| 1 | Frame status, bit 0 is 1 during the VS pulse and bit 1 during vertical blanking | R |
| 2 | Frame counter, one unit at each start of vertical blanking | R |
| 3 | Geometry, width on bits 15:0 and height on bits 31:16 | R |
| 4 | Format, bits per pixel on 7:0, magnification on 15:8, bits per channel on 23:16 and bit 24 at 1 in the indexed format | R |
| 8 | Mode (section 4.1) | R |
| 9 | Transmitter status (section 4.1) | R |
| 10 | Interrupt enable (section 8) | R/W |
| 11 | Pending interrupts (section 8) | R/W1C |
| 12 | Initialization sequencer control (section 7.3) | W |
| 13 | Sequencer counters (section 7.3) | R |
| 14 | Pixel clock of the mode in kHz | R |
| 256 to 511 | Palette of 256 entries of 24 bits, indexed format only | W |
| `2^(addr_width-1)` onward | Framebuffer, one word per address | W |

An address without a register reads zero and ignores the write. The framebuffer and the palette cannot be read. With `addr_width` equal to 16 the window is 256 KiB and the framebuffer starts at the byte offset `0x20000`.

A write to the framebuffer stores only the bytes marked in `i_byteena`, so an `sw` replaces four indexed pixels or two RGB565 pixels, an `sh` replaces half of that and an `sb` replaces one byte. A palette write needs the three low lanes, and the color takes the low 24 bits of the data. A framebuffer or palette write reaches the memory one system cycle after the write pulse.

### 4.1. HDMI registers

| Word | Bits | Name | Description |
| :--- | :--- | :--- | :--- |
| 8 | 7:0 | `MODE_ID` | CEA-861 mode number from the `mode_id` generic |
| 8 | 8 | `HS_POS` | 1 if the horizontal sync is positive |
| 8 | 9 | `VS_POS` | 1 if the vertical sync is positive |
| 9 | 0 | `INT` | 1 while the interrupt pin of the transmitter is active |
| 9 | 1 | `BUSY` | 1 while the sequencer writes to the chip |
| 9 | 2 | `DONE` | 1 after the whole table was written, until the next restart |
| 9 | 3 | `NACK` | 1 if any write of the table got no acknowledge from the chip |
| 9 | 4 | `INIT` | 1 if the instance has the sequencer |
| 14 | 31:0 | `PIXEL_KHZ` | The `pixel_clock_khz` generic |

All write registers clear on reset, and the generic readbacks keep their values.

## 5. Pixel format and memory

A framebuffer stores `32 / bits per pixel` pixels per word, with the lowest-index pixel on the least significant bits.

| `pixel_format` | Bits per pixel | Decoding |
| :--- | :--- | :--- |
| `"indexed"` | 8 | The byte is an index from 0 to 255, and the palette returns the 24-bit color (red on 23:16, green on 15:8 and blue on 7:0) |
| `"direct"` | 16 | RGB565, with red on 15:11, green on 10:5 and blue on 4:0, expanded to 24 bits by repeating the high bits of each channel in the missing low bits, so white `0xFFFF` becomes `0xFFFFFF` |

The format register (word 4) reports 5 bits per channel in the direct format, which is the size of the red and blue channels; the green channel has 6 bits.

### 5.1. Resolutions that fit the DE10-Nano

The FPGA of the DE10-Nano has 5570 kbit of embedded memory, in 557 M10K blocks of 10 kbit. The framebuffer uses four lanes of 8 bits, and each lane takes blocks of 1024 words, so

$$\text{blocks} = 4 \cdot \left\lceil \frac{\text{words}}{1024} \right\rceil \qquad \text{words} = \frac{\text{width} \cdot \text{height} \cdot \text{bits per pixel}}{32}$$

The palette of the indexed format uses one more block, of 256 entries of 24 bits. The table gives the estimate for 16:9 and 4:3 framebuffers, with the magnification that takes them to a CEA-861 mode. The count is made on the organization above, not on a synthesis report.

| Framebuffer | Format | Words | M10K blocks | Fits in 557 | Magnification for the mode |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 320x180 | indexed | 14400 | 61 | yes | 4 for 1280x720, 6 for 1920x1080 |
| 480x270 | indexed | 32400 | 129 | yes | 4 for 1920x1080 |
| 640x360 | indexed | 57600 | 229 | yes | 2 for 1280x720, 3 for 1920x1080 |
| 640x480 | indexed | 76800 | 301 | yes | 1 for 640x480 |
| 800x600 | indexed | 120000 | 473 | yes | 1 for an 800x600 mode |
| 960x540 | indexed | 129600 | 509 | yes | 2 for 1920x1080 |
| 1280x720 | indexed | 230400 | 901 | no | |
| 320x180 | RGB565 | 28800 | 116 | yes | 4 for 1280x720, 6 for 1920x1080 |
| 480x270 | RGB565 | 64800 | 256 | yes | 4 for 1920x1080 |
| 640x360 | RGB565 | 115200 | 452 | yes | 2 for 1280x720, 3 for 1920x1080 |
| 640x480 | RGB565 | 153600 | 600 | no | |

A framebuffer at the native 1280x720 or 1920x1080 resolution does not fit in the FPGA memory and would need external memory, which is outside the peripheral.

## 6. Timing

### 6.1. Mode parameters

Each direction has a visible area, front porch, sync and back porch, and the total is the sum of the four.

$$H_{total} = h\_visible + h\_front\_porch + h\_sync + h\_back\_porch$$

$$V_{total} = v\_visible + v\_front\_porch + v\_sync + v\_back\_porch$$

The column $h$ and the line $v$ advance at every pixel cycle. The pulse starts at $h_s = h\_visible + h\_front\_porch$ and at $v_s = v\_visible + v\_front\_porch$, and the outputs hold the pulse level when

$$h_s \le h < h_s + h\_sync \qquad v_s \le v < v_s + v\_sync$$

The pulse level is 1 for a positive polarity and 0 for a negative one, and the idle level is the opposite. DE is 1 over the whole visible area, in the $h\_visible$ columns of each of the $v\_visible$ lines, and the frame rate is $f_{pixel} / (H_{total} \cdot V_{total})$.

### 6.2. Documented CEA-861 modes

| Mode | VIC | Visible | Front porch | Sync | Back porch | Total | Polarity | Pixel clock |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 640x480p60, horizontal | 1 | 640 | 16 | 96 | 48 | 800 | negative | 25.2 MHz |
| 640x480p60, vertical | 1 | 480 | 10 | 2 | 33 | 525 | negative | |
| 720x480p60, horizontal | 2 | 720 | 16 | 62 | 60 | 858 | negative | 27.0 MHz |
| 720x480p60, vertical | 2 | 480 | 9 | 6 | 30 | 525 | negative | |
| 1280x720p60, horizontal | 4 | 1280 | 110 | 40 | 220 | 1650 | positive | 74.25 MHz |
| 1280x720p60, vertical | 4 | 720 | 5 | 5 | 20 | 750 | positive | |
| 1920x1080p60, horizontal | 16 | 1920 | 88 | 44 | 148 | 2200 | positive | 148.5 MHz |
| 1920x1080p60, vertical | 16 | 1080 | 4 | 5 | 36 | 1125 | positive | |

The nominal pixel clock of 640x480 is 25.175 MHz; at 25.2 MHz a frame lasts $800 \cdot 525 / 25.2\,\text{MHz}$ = 16.67 ms, or 60 frames per second. The ADV7513 accepts a pixel clock of up to 165 MHz, and the board manual uses 25, 27 and 148.5 MHz for the 640x480, 720x480 and 1080p modes of its example. The PLL of the board top level generates the clock of the chosen mode, and the top level passes the timing of the mode to the generics.

### 6.3. Image position and latency

The magnified image has $W = \text{fb\_width} \cdot \text{scale}$ columns and $H = \text{fb\_height} \cdot \text{scale}$ lines, and starts at

$$x_0 = \frac{h\_visible - W}{2} \qquad y_0 = \frac{v\_visible - H}{2}$$

Outside the image the three colors are zero, but DE stays at 1 over the whole visible area. The framebuffer memory reads in one cycle, the pixel pick takes a second and the output register a third. Colors, DE, HS and VS cross the same three stages and leave aligned, three pixel cycles after the counters.

## 7. Transmitter initialization

### 7.1. I2C writer

With `init_enable`, the peripheral writes ADV7513 registers with no help from software. The I2C writer is a single-master, write-only master with a 7-bit address, which generates for each pair a transaction of start, slave address with the write bit, register, value and stop, with an acknowledge after each byte. Each bit lasts four quarters of the SCL period, and one quarter lasts $\lfloor clk\_freq / (4 \cdot i2c\_freq) \rfloor$ system cycles. The acknowledge is sampled in the middle of the SCL pulse and, if missing, the transaction goes on to the stop and the write is counted as not acknowledged. Clock stretching by the slave is not handled.

### 7.2. Initialization table

The table is the `init_table` generic, a string with four hexadecimal digits per entry, the register and then the value, in write order. The string `"980301001520"` writes 0x03 to register 0x98, 0x00 to 0x01 and 0x20 to 0x15. The table takes up to 255 entries, and an empty string makes the sequencer only mark the end.

The DE10-Nano manual says that the example of Terasic uses 24-bit RGB in 4:4:4, that the video format and the audio frequency are in register 0x15 and that the format of register 0xAF must also be observed, and it points to the document `ADV7513_Programming_Guide_R0.pdf` for the values. That guide is not part of the board manual, so the platform supplies every value in the `init_table` generic, and the peripheral ships no default value. The pairs used in the tests are illustrative and do not configure the chip.

The default 7-bit address of the transmitter is `0x39`, the 8-bit write address `0x72` of the chip without the write bit, and it is the `i2c_dev_addr` generic.

### 7.3. Sequencer control

| Word | Bits | Access | Description |
| :--- | :--- | :--- | :--- |
| 12 | 0 | W | Writing 1 restarts the table if the sequencer is stopped; during the sequence the write is ignored |
| 13 | 7:0 | R | Entries written since the start, saturated at 255 |
| 13 | 15:8 | R | Writes without acknowledge since the start, saturated at 255 |
| 13 | 23:16 | R | Entries of the table |

With `init_auto_start` true the sequence starts by itself after reset. Without `init_enable` the I2C outputs stay released and a write to the control register is ignored, which leaves the pins to a software I2C controller.

## 8. Interrupts

The `o_irq` output is 1 while any pending interrupt is enabled. The two registers have the same bits.

| Bit | Event |
| :--- | :--- |
| 0 | End of frame, the rising edge of vertical blanking |
| 1 | Activation of the interrupt pin of the transmitter, the edge to the active level of `int_active_low` |

A bit of `IRQ_PEND` rises with the event and falls only when the processor writes 1 to it. An event in the same cycle as the clear wins over the clear. Reading `IRQ_PEND` has no side effect. The state of the pin also shows on bit 0 of the status register (word 9).

## 9. Wiring in the board top level

1. The PLL of the top level generates `i_pixel_clk` at the frequency of the mode and takes the same clock to the `HDMI_TX_CLK` pin through `o_tx_clk`.
2. The 24 bits of `o_tx_d`, `o_tx_de`, `o_tx_hs` and `o_tx_vs` go to the `HDMI_TX_D[23:0]`, `HDMI_TX_DE`, `HDMI_TX_HS` and `HDMI_TX_VS` pins.
3. `HDMI_TX_INT` enters `i_tx_int`.
4. The tristate layer connects `I2C_SCL` and `I2C_SDA` to the open-drain ports, with the pin in high impedance when the enable is 0.
5. The .sdc declares `i_clk` and `i_pixel_clk` as asynchronous clocks.

## 10. C example

The program loads an eight-color palette, draws eight vertical bars of 40 pixels in a 320x180 indexed framebuffer (magnified 4 times to 1280x720), waits for the chip initialization, turns the display on and counts frames by polling the pending interrupt.

```c
#include <stdint.h>

/* Peripheral base, defined by the platform. */
#define HDMI_BASE 0x40000000u
#define HDMI_REG(word) (*(volatile uint32_t *)(HDMI_BASE + 4u * (word)))

#define REG_CTRL      0u
#define REG_STATUS    9u
#define REG_IRQ_PEND  11u
#define REG_PALETTE   256u
/* addr_width = 16, framebuffer on the upper half of the window. */
#define REG_FB        (1u << 15)

#define STATUS_DONE   (1u << 2)
#define STATUS_INIT   (1u << 4)
#define IRQ_FRAME     (1u << 0)

#define FB_WIDTH      320u
#define FB_HEIGHT     180u
#define BAR_WIDTH     40u
#define BARS          8u

static const uint32_t bar_colors[BARS] = {
    0xFFFFFFu, 0xFFFF00u, 0x00FFFFu, 0x00FF00u,
    0xFF00FFu, 0xFF0000u, 0x0000FFu, 0x000000u,
};

static void draw_bars(void)
{
    /* Four indexed pixels per word; a bar covers 10 words. */
    for (uint32_t row = 0; row < FB_HEIGHT; row++) {
        for (uint32_t word = 0; word < FB_WIDTH / 4u; word++) {
            uint32_t bar = (word * 4u) / BAR_WIDTH;
            HDMI_REG(REG_FB + row * (FB_WIDTH / 4u) + word) = bar * 0x01010101u;
        }
    }
}

int main(void)
{
    for (uint32_t i = 0; i < BARS; i++) {
        HDMI_REG(REG_PALETTE + i) = bar_colors[i];
    }
    draw_bars();

    /* With the sequencer, wait for the table to reach the transmitter. */
    if (HDMI_REG(REG_STATUS) & STATUS_INIT) {
        while (!(HDMI_REG(REG_STATUS) & STATUS_DONE)) {
        }
    }

    HDMI_REG(REG_CTRL) = 1u;

    uint32_t frames = 0;
    for (;;) {
        if (HDMI_REG(REG_IRQ_PEND) & IRQ_FRAME) {
            HDMI_REG(REG_IRQ_PEND) = IRQ_FRAME;
            frames++;
        }
    }
}
```

## 11. Verification

| Check | Coverage |
| :--- | :--- |
| Entity tests `HdmiTxIndexed` and `HdmiTxDirect` | Behavioral monitor that measures line width, frame width, polarities, HS and VS pulse widths, DE and porches, and checks every pixel of two frames against the framebuffer and the palette, with the display on and off; register map, end-of-frame interrupt and transmitter pin interrupt |
| Entity tests `HdmiTxCea640x480`, `HdmiTxCea720x480`, `HdmiTxCea1280x720` and `HdmiTxCea1920x1080` | Line and frame width, pulses, polarities, DE and porches measured in the four CEA-861 modes with the pixel clock of each |
| Entity tests `HdmiTxInit` and `HdmiTxNoInit` | ADV7513 I2C slave model that records the initialization writes (order, address, value), restart, count of writes without acknowledge and free pins without the sequencer |
| Entity tests `HdmiI2cWriter`, `HdmiInitSeq`, `HdmiInitSeqManual` and `HdmiInitSeqEmpty` | Transaction, acknowledge, SCL period at 100 kHz, automatic and manual start, NACK and empty table |
| Entity tests `HdmiScanoutIndexed`, `HdmiScanoutDirect`, `HdmiOut` and `HdmiRegs` | Pixel pick, palette, RGB565 expansion, latency, color mask, reset, interrupts and the read of each word |
| Formal proofs `hdmitim_*`, `hdmiregs_*`, `hdmiseq_*` and `hdmii2c_*` | Timing generator counts against the generics (induction and a measure on the outputs only), HDMI registers and interrupts (induction), sequencer order and counts, open-drain protocol of the I2C writer, with mutants of each block |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
