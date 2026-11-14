# VGA Video

🌐 [Português](../../pt-br/video/video.md) · [English](../../en/video/video.md)

## 1. Reference

The peripheral generates the VESA 640x480 at 60 Hz VGA mode, with 800 x 525 total pixels per frame and negative-polarity horizontal and vertical syncs. The nominal pixel clock is 25.175 MHz; at 25 MHz a frame lasts $800 \cdot 525 / 25\,\text{MHz} = 16.8\ \text{ms}$, or 59.52 frames per second, well within monitor tolerance. The DE0-CV board drives a resistor-ladder DAC of 4 bits per channel (`VGA_R`, `VGA_G` and `VGA_B`), plus the `VGA_HS` and `VGA_VS` pins.

## 2. What it is

The processor writes pixels into a framebuffer, and an independent scan-out reads them and sends them to the monitor. The framebuffer lives in a dual-port memory with independent clocks, written on the system clock and read on the pixel clock. Each framebuffer pixel covers `scale` x `scale` screen pixels, and the image is centered, with black bars over what is left of the 640x480 frame. The pixel clock comes from outside the peripheral, normally from a PLL of the board top level.

| Generic | Default | Meaning |
| :--- | :--- | :--- |
| `fb_width` | 320 | Framebuffer width in pixels; a row must fill a whole number of 32-bit words |
| `fb_height` | 200 | Framebuffer height in pixels |
| `pixel_bits` | 16 | Bits per pixel, 16 for RGB444 or 8 for an index into a 256-color palette |
| `scale` | 2 | Magnification in x and in y; the magnified image must fit in 640x480 |
| `addr_width` | 16 | Width of the window word address, at least 11 and larger than the framebuffer address |

With the default values the image is 640x400 and the black bars are 40 lines at the top and 40 at the bottom.

## 3. Interface

| Port | Direction | Function |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | System clock and synchronous reset, active at 1 |
| `i_pixel_clk` | input | Pixel clock, asynchronous to `i_clk` |
| `i_data_in`, `i_address` | input | `word_t` write data (`XLEN` bits) and word address of `addr_width` bits |
| `i_byteena` | input | Write byte enables, one bit per byte |
| `i_write` | input | Write pulse from the processor |
| `o_data_out` | output | Read data, combinational on the address |
| `o_vga_r`, `o_vga_g`, `o_vga_b` | output | Color channels of 4 bits each |
| `o_vga_hs`, `o_vga_vs` | output | Horizontal and vertical syncs, active low |

A read has no side effect, so there is neither a read pulse nor an interrupt. The system reset must last at least three `i_pixel_clk` cycles, because it reaches the pixel domain through a two-stage synchronizer.

## 4. Address map

Accesses are 32 bits wide, and the addresses below are word addresses. The most significant bit of `i_address` separates the framebuffer window from the register space.

| Word address | Content | Access |
| :--- | :--- | :--- |
| 0 | Control, bit 0 turns the framebuffer display on (reset 0) | R/W |
| 1 | Status, bit 0 is 1 during the vertical sync pulse and bit 1 is 1 during the vertical blanking | R |
| 2 | Frame counter, one unit at every start of vertical blanking, cleared on reset | R |
| 3 | Geometry, framebuffer width in bits 15:0 and height in bits 31:16 | R |
| 4 | Format, bits per pixel in bits 7:0 and magnification in bits 15:8 | R |
| 256 to 511 | Palette of 256 RGB444 entries, present only when `pixel_bits` is 8 | W |
| `2^(addr_width-1)` onward | Framebuffer, one word per address | W |

An address without a register reads zero and ignores the write. The framebuffer and the palette cannot be read. A write to the window past the last framebuffer word is discarded.

With `addr_width` equal to 16 the window is 256 KiB and the framebuffer starts at offset `0x20000`. A platform that reserves a window larger than the peripheral one wires only the low `addr_width` bits of the word address to it.

### 4.1. Byte-masked write

A framebuffer write stores only the bytes marked in `i_byteena`, so an `sw` access changes two 16-bit pixels at once, an `sh` changes one pixel and an `sb` changes one byte. A palette write needs the two low lanes, that is, a halfword or a word; a one-byte access is ignored. The control register changes when byte 0 is enabled. A framebuffer or palette write reaches the memory one system clock cycle after the write pulse.

## 5. Pixel format

A framebuffer holds `32 / pixel_bits` pixels per word, with the lowest-index pixel in the least significant bits, which is the byte order of the processor.

| `pixel_bits` | Pixel | Decoding |
| :--- | :--- | :--- |
| 16 | Bits 11:8 red, 7:4 green and 3:0 blue; bits 15:12 are ignored | Direct, one RGB444 color |
| 8 | Index from 0 to 255 | The palette returns the 12-bit RGB444 color, in bits 11:0 of the entry |

The framebuffer pixel of index $n$, counted by rows, sits in word $\lfloor n \cdot \text{pixel\_bits} / 32 \rfloor$.

## 6. Timing

### 6.1. Mode parameters

| Direction | Visible | Front porch | Sync | Back porch | Total | Polarity |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Horizontal, in pixels | 640 | 16 | 96 | 48 | 800 | negative |
| Vertical, in lines | 480 | 10 | 2 | 33 | 525 | negative |

The column $h$ and the line $v$ advance every pixel cycle, with $h$ from 0 to 799 and $v$ from 0 to 524. The outputs are

$$o\_vga\_hs = 0 \iff 656 \le h < 752 \qquad o\_vga\_vs = 0 \iff 490 \le v < 492$$

### 6.2. Diagram

One line, with time in pixel cycles. The HS pulse lasts 96 cycles.

```
 h        0                    640   656      752       800
          |<--- visible 640 -->|<-16->|<- 96 ->|<- 48 ->|
 o_vga_hs ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\________/‾‾‾‾‾‾‾
 color    [  image or black   ]   black     black
```

One frame, with time in lines. The VS pulse lasts 2 lines, or 1600 cycles.

```
 v        0                          480  490 492        525
          |<------ visible 480 ----->|<10>|2|<--- 33 ---->|
 o_vga_vs ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_/‾‾‾‾‾‾‾‾‾‾‾‾
 vblank   ___________________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 vsync    ______________________________/‾\___________________
```

### 6.3. Image position

The magnified image has $W = \text{fb\_width} \cdot \text{scale}$ columns and $H = \text{fb\_height} \cdot \text{scale}$ lines, and starts at

$$x_0 = \frac{640 - W}{2} \qquad y_0 = \frac{480 - H}{2}$$

The screen pixel $(x, y)$ inside the image shows the framebuffer pixel of column $\lfloor (x - x_0) / \text{scale} \rfloor$ and row $\lfloor (y - y_0) / \text{scale} \rfloor$. Outside the image the three colors are zero.

### 6.4. Latency

The framebuffer memory reads in one cycle, the pixel selection takes a second and the outputs are registered in a third. The syncs go through the same three stages, so colors, HS and VS leave aligned, three pixel cycles after the counters. The status bits the processor sees come from the counters, without that delay.

## 7. Clock domains

| Signal | Source | Destination | Crossing |
| :--- | :--- | :--- | :--- |
| Reset | `i_clk` | `i_pixel_clk` | Two-stage synchronizer |
| Display enable | `i_clk` | `i_pixel_clk` | Two-stage synchronizer |
| Vertical sync and blanking | `i_pixel_clk` | `i_clk` | Two bits registered in the pixel domain and a two-stage synchronizer |
| Framebuffer and palette data | `i_clk` | `i_pixel_clk` | Dual-port memory, one port on each clock |

The signals that cross through a synchronizer are long levels, at least 1600 pixel cycles, and no data bus goes through a synchronizer. A processor write to the same address the scan-out reads in that cycle shows the old or the new data, with no other effect. The constraints file of the platform must declare the path into the first stage of each synchronizer as false or with a maximum delay, and the path between the two memory ports as false, because there is no phase relation between the clocks.

## 8. Memory

The framebuffer uses a 32-bit wide memory in four byte lanes, one array per lane, so that Quartus infers M10K blocks with byte enables. An M10K block holds 10240 bits.

$$\text{words} = \frac{\text{fb\_width} \cdot \text{fb\_height} \cdot \text{pixel\_bits}}{32} \qquad \text{blocks per lane} = \left\lceil \frac{\text{words}}{1024} \right\rceil$$

| Configuration | Words | M10K blocks | Useful bits |
| :--- | :--- | :--- | :--- |
| 320x200, `pixel_bits` 16 | 32000 | 128 at most, 96 if Quartus removes the 4 high bits of each pixel that the scan-out never reads | 1 024 000 |
| 320x200, `pixel_bits` 8 | 16000 | 64 plus 1 for the palette | 512 000 |

The DE0-CV has 308 M10K blocks. The palette of 256 entries of 12 bits fits in one block.

## 9. Software use

1. Write pixel $n$ to the framebuffer through the window, in 32-bit words with the wanted byte mask.
2. Write 1 to the control register to display the framebuffer.
3. To change the content without tearing, read the frame counter, wait for it to change (start of vertical blanking) and then write; the blanking lasts 45 lines, or about 1.4 ms.

## 10. Verification

| Verification | Coverage |
| :--- | :--- |
| Entity tests `Video`, `VideoSmall`, `VideoScale3` and `VideoPalette` | Reset and registers, exact cycle count of HS and VS, the visible area and the black bars pixel by pixel against a model, the duplication in x and in y, random byte-masked writes including outside the useful window, the palette, the vertical sync bit, the frame counter and the clock crossing at three clock ratios |
| Entity tests `VideoTiming`, `VideoTimingScale3` and `VideoTimingFull` | Counters, syncs, image rectangle and framebuffer coordinates, including the 640x480 image without bars |
| Entity tests `VideoDpram` and `VideoDpramNarrow` | Per-lane write, registered read and clock ratios |
| Entity tests `VideoRegs` and `VideoRegsPalette` | Decoding, byte mask, edge counter and registered writes |
| Entity tests `VideoScanout` and `VideoScanoutPalette` | Address, pixel selection, palette, three-cycle latency and enable |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
