# HDMI output with TMDS straight from the FPGA

🌐 [Português](../../pt-br/HDMI/hdmi_tmds_tx.md) · [English](../../en/HDMI/hdmi_tmds_tx.md)

## 1. What it is

`hdmi_tmds_tx` is the HDMI video output of the processor for a board whose connector is wired straight to the FPGA pins, with no external transmitter chip, such as the MKR Vidor 4000. The processor writes pixels into a framebuffer, an independent scan-out reads them, and the TMDS transmitter serializes the result onto the three data pairs and the clock pair of the connector.

The wrapper is structural and has no logic of its own. It composes two entities that have their own documents.

| Entity | Role in this wrapper |
| :--- | :--- |
| `hdmi_tx`, without the ADV7513 sequencer | Video and HDMI registers, palette, dual-port framebuffer, timing and scan-out; delivers the 24-bit parallel RGB video with DE, HS and VS on the pixel clock |
| `tmds_tx` | Encodes the video as TMDS and serializes the four pairs with the serial clock |

The address map, the timing by generics, the pixel formats and the interrupts are those of `hdmi_tx`, summarized in section 4, and the differences are in section 5.

## 2. Clock domains

| Clock | Frequency | Domain |
| :--- | :--- | :--- |
| `i_clk` | system | Registers, write windows and interrupts |
| `i_pixel_clk` | pixel clock of the mode, asynchronous to `i_clk` | Timing, scan-out and TMDS encoding |
| `i_serial_clk` | $5 \times$ `i_pixel_clk`, from the same PLL | Serialization of the pairs |

With 720p60 the pixel and serial clocks are 74.25 MHz and 371.25 MHz, and with 480p60 they are 27 MHz and 135 MHz. The system reset crosses to the pixel domain through a two-stage synchronizer and must last at least three cycles of `i_pixel_clk`.

## 3. Interface

### 3.1. Generics

The mode and framebuffer generics have the meaning and the default of `hdmi_tx`. There are no `clk_freq`, `init_*`, `i2c_*` or `int_active_low`, which belong to the sequencer and to the interrupt pin of the ADV7513.

| Generic | Default | Meaning |
| :--- | :--- | :--- |
| `fb_width`, `fb_height` | 320, 180 | Framebuffer size; a line must fill a whole number of 32-bit words |
| `pixel_format` | `"indexed"` | `"indexed"` (8 bits with a 24-bit palette) or `"direct"` (16-bit RGB565) |
| `scale` | 4 | Magnification in x and y; the magnified image must fit in the visible area |
| `addr_width` | 16 | Width of the word address of the window, at least 11 and larger than the framebuffer address |
| `h_visible`, `v_visible` | 1280, 720 | Visible pixels per line and visible lines per frame |
| `h_front_porch`, `v_front_porch` | 110, 5 | Front porches |
| `h_sync`, `v_sync` | 40, 5 | Width of the sync pulse in pixels and in lines |
| `h_back_porch`, `v_back_porch` | 220, 20 | Back porches |
| `h_sync_positive`, `v_sync_positive` | true, true | Pulse polarity, true for high level during the pulse |
| `mode_id` | 4 | CEA-861 mode number (VIC), or 0 for a custom mode; informative only |
| `pixel_clock_khz` | 74250 | Pixel clock of the mode in kHz; informative only, the real clock comes from the PLL |
| `lane_invert` | `0000` | One bit per pair, 0 blue, 1 green, 2 red and 3 clock; 1 inverts a pair wired backwards on the board |
| `device_family` | `"Cyclone 10 LP"` | Family passed to the output DDR register of the board |

### 3.2. Ports

| Port | Direction | Function |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | System clock and synchronous reset, active high |
| `i_pixel_clk` | input | Pixel clock |
| `i_serial_clk` | input | Serial clock, five times the pixel clock |
| `i_data_in`, `i_address` | input | 32-bit write data and word address of `addr_width` bits |
| `i_byteena` | input | Byte enables of the write, one bit per byte |
| `i_write` | input | Write pulse from the processor |
| `o_data_out` | output | Read data, combinational on the address |
| `o_irq` | output | Level interrupt, for end of frame or monitor connection, according to the masks |
| `i_hpd` | input | Monitor connection detect, active high, asynchronous |
| `o_tmds_d` | output, 3 bits | Data pairs, positive side: 0 blue, 1 green, 2 red |
| `o_tmds_clk` | output | Clock pair, positive side |

The outputs are the positive side of each pair; the negative side comes from the Quartus differential pin assignment of the same output.

## 4. Address map

Accesses are 32 bits wide and the addresses are word addresses. The most significant bit of `i_address` separates the framebuffer window from the register space. An address with no register reads zero and ignores writes, and the framebuffer and the palette cannot be read.

| Word address | Content | Access |
| :--- | :--- | :--- |
| 0 | Control, bit 0 turns the framebuffer display on (reset 0) | R/W |
| 1 | Frame status, bit 0 is 1 during the VS pulse and bit 1 during vertical blanking | R |
| 2 | Frame counter, one unit at every start of vertical blanking | R |
| 3 | Geometry, width in bits 15:0 and height in bits 31:16 | R |
| 4 | Format, bits per pixel in 7:0, magnification in 15:8, bits per channel in 23:16 and bit 24 at 1 in the indexed format | R |
| 8 | Mode, `mode_id` in 7:0 and the HS and VS polarity in bits 8 and 9 | R |
| 9 | HDMI status (section 5) | R |
| 10 | Interrupt enable, bit 0 for end of frame and bit 1 for monitor connection | R/W |
| 11 | Pending interrupts, same bits; writing 1 clears | R/W1C |
| 14 | Pixel clock of the mode in kHz | R |
| 256 to 511 | Palette of 256 24-bit entries, indexed format only | W |
| `2^(addr_width-1)` onward | Framebuffer, one word per address, with byte-wise writes | W |

## 5. Differences from `hdmi_tx`

| Topic | Behavior |
| :--- | :--- |
| HDMI status, word 9, bit 0 (`INT`) | Reflects `i_hpd`, 1 with the monitor connected |
| Interrupt of bit 1 | Rises on the activation of `i_hpd`, that is, when the monitor is connected |
| HDMI status, word 9, bits 4:1 | Read 0, because there is no sequencer; the restart at word 12 has no effect |
| DDC channel of the connector (SCL and SDA) | Does not go through this block; the top level wires it to a general-purpose I2C master, which reads the monitor EDID by software |

## 6. Use

1. Write the palette (indexed format) and the pixels in the framebuffer window.
2. Write 1 to word 0 to turn the display on.
3. Read word 9 to know whether a monitor is connected, and enable the interrupt of bit 1 at word 10 to be told of the connection.

## 7. Verification

| Check | What it verifies |
| :--- | :--- |
| cocotb `HdmiTmdsTx` | Samples the four pairs on both edges of the serial clock, decodes the symbols back into pixels and syncs, and checks every pixel of four frames against the framebuffer and the timing; checks the status and the connection interrupt |
| Formal proof `hdmitmds_*` | With the three clocks free, bit 0 of the status is the `i_hpd` pin through the two-stage synchronizer of the system clock and the other bits of the status word read 0; with mutants of the pin tied to 0 and of the inverted pin |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
