# VGA Video

🌐 [Português](../../pt-br/video/video.md) · [English](../../en/video/video.md)

## 1. Reference

The peripheral generates any VGA video mode from generics, without knowing the board or its pins. The default mode is the VESA 640x480 at 60 Hz, with 800 x 525 total pixels per frame and negative-polarity syncs. The nominal pixel clock is 25.175 MHz; at 25 MHz a frame lasts $800 \cdot 525 / 25\,\text{MHz} = 16.8\ \text{ms}$, or 59.52 frames per second, well within monitor tolerance.

The width of each color channel is also a generic. The DE0-CV drives a resistor-ladder DAC of 4 bits per channel, and the DE2-115 an ADV7123 of 8 bits per channel, which also needs the blanking and composite sync signals.

## 2. What it is

The processor writes pixels into a framebuffer, and an independent scan-out reads them and sends them to the monitor. The framebuffer lives in a dual-port memory with independent clocks, written on the system clock and read on the pixel clock. Each framebuffer pixel covers `scale` x `scale` screen pixels, and the image is centered in the visible area, with black bars over what is left of the frame. The pixel clock comes from outside the peripheral, normally from a PLL of the board top level.

### 2.1. Generics

| Generic | Default | Meaning |
| :--- | :--- | :--- |
| `fb_width` | 320 | Framebuffer width in pixels; a row must fill a whole number of 32-bit words |
| `fb_height` | 200 | Framebuffer height in pixels |
| `channel_bits` | 4 | Bits of each color channel, from 1 to 10 (4 on the DE0-CV, 8 on the DE2-115) |
| `pixel_format` | `"indexed"` | Pixel format, `"indexed"` or `"direct"` (section 5) |
| `scale` | 2 | Magnification in x and in y; the magnified image must fit in the visible area |
| `addr_width` | 16 | Width of the window word address, at least 11 and larger than the framebuffer address |
| `h_visible`, `v_visible` | 640, 480 | Visible pixels per line and visible lines per frame |
| `h_front_porch`, `v_front_porch` | 16, 10 | Front porches, between the end of the visible area and the sync pulse |
| `h_sync`, `v_sync` | 96, 2 | Sync pulse width in pixels and in lines |
| `h_back_porch`, `v_back_porch` | 48, 33 | Back porches, between the sync pulse and the visible area |
| `h_sync_positive`, `v_sync_positive` | false, false | Pulse polarity, true for a high level during the pulse |

With the default values the image is 640x400 and the black bars are 40 lines at the top and 40 at the bottom. The timing values of each mode come from the mode catalog of the board, and the top-level generator passes them to the peripheral.

## 3. Interface

| Port | Direction | Function |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | System clock and synchronous reset, active at 1 |
| `i_pixel_clk` | input | Pixel clock, asynchronous to `i_clk` |
| `i_data_in`, `i_address` | input | 32-bit write data and word address of `addr_width` bits |
| `i_byteena` | input | Write byte enables, one bit per byte |
| `i_write` | input | Write pulse from the processor |
| `o_data_out` | output | Read data, combinational on the address |
| `o_vga_r`, `o_vga_g`, `o_vga_b` | output | Color channels of `channel_bits` bits each |
| `o_vga_hs`, `o_vga_vs` | output | Horizontal and vertical syncs, with the polarity of the mode |
| `o_vga_blank_n` | output | DAC blanking, low outside the visible area (`VGA_BLANK_N` pin of the ADV7123) |
| `o_vga_sync_n` | output | DAC composite sync, always low (`VGA_SYNC_N` pin of the ADV7123) |

On the DE0-CV the last two signals are left unconnected. On the DE2-115 the top level also connects `i_pixel_clk` to the `VGA_CLK` pin of the DAC.

A read has no side effect, so there is neither a read pulse nor an interrupt. The system reset must last at least three `i_pixel_clk` cycles, because it reaches the pixel domain through a two-stage synchronizer.

## 4. Address map

Accesses are 32 bits wide, and the addresses below are word addresses. The most significant bit of `i_address` separates the framebuffer window from the register space.

| Word address | Content | Access |
| :--- | :--- | :--- |
| 0 | Control, bit 0 turns the framebuffer display on (reset 0) | R/W |
| 1 | Status, bit 0 is 1 during the vertical sync pulse and bit 1 is 1 during vertical blanking | R |
| 2 | Frame counter, one unit at each start of vertical blanking, cleared on reset | R |
| 3 | Geometry, framebuffer width in bits 15:0 and height in bits 31:16 | R |
| 4 | Format, bits per pixel in bits 7:0, magnification in bits 15:8, bits per channel in bits 23:16 and bit 24 at 1 in the indexed format | R |
| 256 to 511 | Palette of 256 entries of $3 \cdot$ `channel_bits` bits, exists only in the indexed format | W |
| `2^(addr_width-1)` onward | Framebuffer, one word per address | W |

An address with no register reads zero and ignores writes. The framebuffer and the palette cannot be read. A write into the window after the last framebuffer word is discarded.

With `addr_width` equal to 16 the window is 256 KiB and the framebuffer starts at offset `0x20000`. A platform that reserves a window larger than the peripheral's connects only the low `addr_width` bits of the word address to it.

### 4.1. Byte-masked writes

A framebuffer write stores only the bytes marked in `i_byteena`, so an `sw` changes four indexed pixels or two direct 16-bit pixels at once, an `sh` changes half of that and an `sb` changes one byte. A palette write requires the low lanes that hold the color, that is, two lanes with 4 bits per channel and three with 8 bits per channel; an access that does not cover them is ignored. The color takes the low $3 \cdot$ `channel_bits` bits of the data, and the rest are ignored. The control register changes if byte 0 is enabled. A framebuffer or palette write reaches the memory one system clock cycle after the write pulse.

## 5. Pixel format

A framebuffer holds `32 / bits per pixel` pixels per word, with the lowest-index pixel in the least significant bits, which is the byte order of the processor.

| `pixel_format` | Bits per pixel | Decoding |
| :--- | :--- | :--- |
| `"indexed"` | 8 | The byte is an index from 0 to 255, and the palette returns the color of $3 \cdot$ `channel_bits` bits |
| `"direct"` | 16 if $3 \cdot$ `channel_bits` $\le 16$, otherwise 32 | The low $3 \cdot$ `channel_bits` bits of the pixel are the color; the remaining high bits are ignored |

In a color, red takes the highest `channel_bits` bits, green the middle ones and blue the lowest. With 4 bits per channel the color is an RGB444, and with 8 bits it is an RGB888.

The indexed format is the default because it is the native format of DOOM, it spares the processor a per-pixel conversion, and it keeps the framebuffer at 8 bits per pixel whatever the channel width of the board. The direct format needs no palette and serves to exercise the video without it.

The framebuffer pixel of index $n$, counted by rows, lies in word $\lfloor n \cdot \text{bits} / 32 \rfloor$.

## 6. Timing

### 6.1. Mode parameters

Each direction has a visible area, a front porch, a sync and a back porch, and the total is the sum of the four.

$$H_{total} = h\_visible + h\_front\_porch + h\_sync + h\_back\_porch$$

$$V_{total} = v\_visible + v\_front\_porch + v\_sync + v\_back\_porch$$

Column $h$ and line $v$ advance on every pixel cycle, with $h$ from 0 to $H_{total}-1$ and $v$ from 0 to $V_{total}-1$. The pulse starts at $h_s = h\_visible + h\_front\_porch$ and at $v_s = v\_visible + v\_front\_porch$, and the outputs take the pulse level when

$$h_s \le h < h_s + h\_sync \qquad v_s \le v < v_s + v\_sync$$

The pulse level is 1 for positive polarity and 0 for negative polarity, and the idle level is the opposite one. The default mode has the values below.

| Direction | Visible | Front porch | Sync | Back porch | Total | Polarity |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Horizontal, in pixels | 640 | 16 | 96 | 48 | 800 | negative |
| Vertical, in lines | 480 | 10 | 2 | 33 | 525 | negative |

### 6.2. Diagram

One line of the default mode, with time in pixel cycles. The HS pulse lasts 96 cycles.

```
 h        0                    640   656      752       800
          |<-- visible 640 --->|<-16->|<- 96 ->|<- 48 ->|
 o_vga_hs ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\________/‾‾‾‾‾‾‾
 color    [  image or black   ]   black     black
```

One frame of the default mode, with time in lines. The VS pulse lasts 2 lines, or 1600 cycles.

```
 v        0                          480  490 492        525
          |<----- visible 480 ------>|<10>|2|<--- 33 ---->|
 o_vga_vs ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_/‾‾‾‾‾‾‾‾‾‾‾‾
 vblank   ___________________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 vsync    ______________________________/‾\___________________
```

The `vsync` and `vblank` status bits read by the processor are 1 during the pulse and after the last visible line, whatever the polarity of the output.

### 6.3. Image position

The magnified image has $W = \text{fb\_width} \cdot \text{scale}$ columns and $H = \text{fb\_height} \cdot \text{scale}$ lines, and starts at

$$x_0 = \frac{h\_visible - W}{2} \qquad y_0 = \frac{v\_visible - H}{2}$$

The screen pixel $(x, y)$ inside the image shows the framebuffer pixel of column $\lfloor (x - x_0) / \text{scale} \rfloor$ and line $\lfloor (y - y_0) / \text{scale} \rfloor$. Outside the image the three colors are zero. A 320x200 image with `scale` 2 in a 1280x720 16:9 mode ($W = 640$, $H = 400$) has side bars of 320 columns and bars of 160 lines at the top and bottom, and with `scale` 3 it fills 960x600.

### 6.4. Latency

The framebuffer memory reads in one cycle, the pixel selection takes a second and the output of the VGA backend is registered in a third. The syncs, the blanking and the image mark go through the same three stages, so colors, HS, VS and `o_vga_blank_n` come out aligned, three pixel cycles after the counters. The status bits seen by the processor come from the counters, without this delay.

## 7. Blocks

| Block | Domain | Function |
| :--- | :--- | :--- |
| `video_timing` | pixel | Column and line counters, syncs with polarity, visible area and framebuffer coordinates |
| `video_scanout` | pixel | Read address, pixel selection in the word, palette and color decoding |
| `video_vga` | pixel | Output register of the channels, syncs and blanking, with the colors blanked outside the image |
| `video_regs` | system | Bus decoding, registers, frame counter and framebuffer and palette writes |
| `video_dpram` | both | Dual-port memory with per-byte-lane writes |
| `video` | both | Top level that only instantiates and connects the blocks and the synchronizers |

## 8. Clock domains

| Signal | From | To | Crossing |
| :--- | :--- | :--- | :--- |
| Reset | `i_clk` | `i_pixel_clk` | Two-stage synchronizer |
| Display enabled | `i_clk` | `i_pixel_clk` | Two-stage synchronizer |
| Vertical sync and blanking | `i_pixel_clk` | `i_clk` | Two bits registered in the pixel domain and a two-stage synchronizer |
| Framebuffer and palette data | `i_clk` | `i_pixel_clk` | Dual-port memory, one port on each clock |

The signals that cross through a synchronizer are long levels, of at least one line of the mode, and no data bus goes through a synchronizer. A processor write to the same address the scan-out reads in that cycle shows the old data or the new, with no other effect. The platform constraints file must declare the path into the first stage of each synchronizer as false or with a maximum delay, and the path between the two memory ports as false, since the clocks have no phase relation.

## 9. Memory

The framebuffer uses a memory 32 bits wide in four byte lanes, one array per lane, so that Quartus infers M10K blocks with byte enables. An M10K block has 10240 bits.

$$\text{words} = \frac{\text{fb\_width} \cdot \text{fb\_height} \cdot \text{bits per pixel}}{32} \qquad \text{blocks per lane} = \left\lceil \frac{\text{words}}{1024} \right\rceil$$

| Configuration | Words | M10K blocks | Useful bits |
| :--- | :--- | :--- | :--- |
| 320x200, indexed | 16000 | 64 plus 1 for the palette | 512 000 |
| 320x200, direct with 4 bits per channel | 32000 | 128 at most, 96 if Quartus removes the 4 high bits of each pixel that the scan-out never reads | 1 024 000 |
| 320x200, direct with 8 bits per channel | 64000 | 256 at most, 192 if Quartus removes the 8 high bits of each pixel that the scan-out never reads | 2 048 000 |

The DE0-CV has 308 M10K blocks. The 256-entry palette fits in one block with 4 bits per channel (12 bits per entry) and in two with 8 bits per channel (24 bits per entry).

## 10. Use from software

1. Read the format register to learn the bits per pixel, the magnification, the bits per channel and whether there is a palette.
2. In the indexed format, write the 256 palette entries, each with the low $3 \cdot$ `channel_bits` bits of the word.
3. Write pixel $n$ into the framebuffer through the window, in 32-bit words with the desired byte mask.
4. Write 1 to the control register to display the framebuffer.
5. To change the content without tearing the image, read the frame counter, wait for it to change (start of vertical blanking) and then write; in the default mode the blanking lasts 45 lines, or about 1.4 ms.

## 11. Verification

| Verification | Coverage |
| :--- | :--- |
| Entity tests `Video`, `VideoDirect`, `VideoSmall`, `VideoScale3`, `VideoPalette`, `VideoIndexedChannel8`, `VideoDirectChannel8`, `VideoTinyMode` and `VideoMixedPolarity` | Reset and registers, exact HS and VS cycle counts at the polarity of the mode, the visible area, the black bars and the blanking pixel by pixel against a model, duplication in x and in y, random byte-masked writes and writes outside the useful window, the palette, the vertical sync bit, the frame counter and the clock crossing at three clock ratios, in both formats, with 4 and 8 bits per channel and in modes of another resolution and polarity |
| Entity tests `VideoTiming`, `VideoTimingScale3`, `VideoTimingFull`, `VideoTimingSvga`, `VideoTimingTiny` and `VideoTimingMixed` | Counters, syncs in both polarities, visible area, image rectangle and framebuffer coordinates, including the 640x480 image with no bars and the 800x600 mode |
| Entity tests `VideoDpram` and `VideoDpramNarrow` | Per-lane write, registered read and clock ratios |
| Entity tests `VideoRegs`, `VideoRegsDirect`, `VideoRegsPalette`, `VideoRegsIndexedChannel8` and `VideoRegsDirectChannel8` | Decoding, format register, byte mask of the palette color, edge counter and registered writes |
| Entity tests `VideoScanout`, `VideoScanoutDirect`, `VideoScanoutPalette`, `VideoScanoutIndexedChannel8` and `VideoScanoutDirectChannel8` | Address, pixel selection, palette, two-cycle latency up to the backend and enable |
| Entity tests `VideoVga` and `VideoVgaChannel8` | Channel split, color blanking, DAC blanking and the reset idle levels in both polarities |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
