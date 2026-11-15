# TMDS transmitter straight to the HDMI connector

🌐 [Português](../../pt-br/HDMI/tmds_tx.md) · [English](../../en/HDMI/tmds_tx.md)

## 1. What it is

TMDS transmitter (`tmds_tx`) for a board whose HDMI connector is wired straight to the FPGA pins, with no external transmitter chip. It takes 24-bit parallel RGB video with DE, HS and VS, the same bus that `hdmi_tx` hands to the ADV7513, and produces the three data channels and the clock channel of the DVI 1.0 TMDS coding. The signal carries no data islands, audio or InfoFrames, and monitors accept it as HDMI video. It is a different entity from `hdmi_tx`, which talks to the ADV7513 over a parallel bus and I2C.

| Entity | Role |
| :--- | :--- |
| `tmds_tx` | Structural top, which wires the encoders, the serializers and the output DDR register |
| `tmds_encoder` | One-channel encoder, from 8 bits to 10 bits, with the running disparity |
| `tmds_serializer` | One-channel serializer, from 10 bits to two bits per cycle of the fast clock |
| `tmds_ddr_out` | Output DDR register, with a simulation model and the wrapper of the Intel `altddio_out` |
| `tmds_consts` | Symbol width, control symbols, clock-channel symbol and the count of bits set |

## 2. Boards

The MKR Vidor 4000 datasheet (section 1.2) lists the Cyclone 10 CL016 FPGA and the Micro HDMI video output, and it carries neither the pin table nor the electrical standard of the connector. The names `oHDMI_TX[2:0]` and `oHDMI_CLK` of that board's outputs come from its reference design, and the correspondence with `o_data` and `o_clk` is the one in the table below.

| Port | TMDS channel | Name on the Vidor |
| :--- | :--- | :--- |
| `o_data(0)` | Channel 0, blue, with HS and VS in blanking | `oHDMI_TX[0]` |
| `o_data(1)` | Channel 1, green | `oHDMI_TX[1]` |
| `o_data(2)` | Channel 2, red | `oHDMI_TX[2]` |
| `o_clk` | Clock channel | `oHDMI_CLK` |

The ports are the positive side of each pair. The negative side comes from the Quartus differential pin assignment on the same output, and the `lane_invert` generic corrects a pair wired backwards on the board.

## 3. Interface

### 3.1. Generics

| Generic | Default | Description |
| :--- | :--- | :--- |
| `lane_invert` | `0000` | One bit per channel (0 blue, 1 green, 2 red, 3 clock); 1 inverts the pair |
| `device_family` | `"Cyclone 10 LP"` | Family passed to `altddio_out` on the board; the simulation model ignores it |

### 3.2. Ports

| Port | Direction | Description |
| :--- | :--- | :--- |
| `i_clk_pixel` | input | Pixel clock of the mode |
| `i_clk_x5` | input | Clock five times faster, from the same PLL, with a fixed phase to the pixel clock |
| `i_rst` | input | Reset synchronous to the pixel clock, active at 1 |
| `i_rgb` | input, 24 bits | Pixel, red on 23:16, green on 15:8 and blue on 7:0 |
| `i_de`, `i_hsync`, `i_vsync` | input | Data enable and syncs, already at the polarity of the mode |
| `o_data` | output, 3 bits | Data pairs, positive side |
| `o_clk` | output | Clock pair, positive side |

The block has no register window. It keeps no state that software configures, and the display enable is the one of the video controller that drives `i_de`, `i_hsync` and `i_vsync`.

## 4. Coding

Each channel encoder runs two stages on the input byte $d$. The first minimizes the transitions and produces nine bits $q_m$, with $N_1(d)$ the number of bits set in $d$.

$$
q_m[0] = d[0], \qquad q_m[i] = q_m[i-1] \oplus d[i] \ \text{(XOR)} \quad \text{or} \quad q_m[i] = \overline{q_m[i-1] \oplus d[i]} \ \text{(XNOR)}
$$

The chain is XNOR with $q_m[8] = 0$ when $N_1(d) > 4$ or when $N_1(d) = 4$ and $d[0] = 0$, and it is XOR with $q_m[8] = 1$ otherwise. The second stage balances the 10-bit symbol with the running disparity $D$ and the difference $\delta = N_1(q_m[7:0]) - N_0(q_m[7:0])$.

| Condition | Bit 9 | Bits 7:0 | New disparity |
| :--- | :--- | :--- | :--- |
| $D = 0$ or $\delta = 0$, with $q_m[8] = 1$ | 0 | $q_m[7:0]$ | $D + \delta$ |
| $D = 0$ or $\delta = 0$, with $q_m[8] = 0$ | 1 | $\overline{q_m[7:0]}$ | $D - \delta$ |
| $D$ and $\delta$ of the same sign | 1 | $\overline{q_m[7:0]}$ | $D - \delta + 2 q_m[8]$ |
| Other cases | 0 | $q_m[7:0]$ | $D + \delta - 2 \overline{q_m[8]}$ |

Bit 8 of the symbol is $q_m[8]$. Outside the visible area ($DE = 0$) the symbol is one of the four control symbols, picked by $C_1 C_0$, and $D$ returns to zero. The blue channel carries $C_0 = HS$ and $C_1 = VS$, and the green and red channels carry zero.

| $C_1 C_0$ | Symbol (bit 9 first) |
| :--- | :--- |
| 00 | `1101010100` |
| 01 | `0010101011` |
| 10 | `0101010100` |
| 11 | `1010101011` |

## 5. Serialization and clocks

The symbol leaves from bit 0 to bit 9. The serializer delivers two bits per cycle of `i_clk_x5`, one for each half of the cycle, so each channel transmits $10$ bits per pixel period and the rate of each pair is ten times the pixel clock. The clock channel transmits the constant symbol `1111100000` (five bits at 0 and then five at 1), one period of the pixel clock.

$$
f_{x5} = 5 \cdot f_{pixel}, \qquad f_{bit} = 10 \cdot f_{pixel}
$$

| Mode | $f_{pixel}$ | $f_{x5}$ |
| :--- | ---: | ---: |
| 480p60 | 27 MHz | 135 MHz |
| 720p60 | 74.25 MHz | 371.25 MHz |

The symbol changes at every edge of the pixel clock and crosses into the fast domain through a hold register and a toggle bit synchronized in two stages, which loads the shift register. The two clocks must come from the same PLL, and the timing constraint of the path from the hold register to the shift register is a multicycle of five cycles of the fast clock.

## 6. Integration

The `tmds_tx` takes the `o_tx_d`, `o_tx_de`, `o_tx_hs` and `o_tx_vs` outputs of `hdmi_tx` directly, without the ADV7513 initialization sequencer. A board platform includes exactly one of `src/HDMI/tmds/sim/tmds_ddr_out.vhd` (simulation) and `src/HDMI/tmds/altera/tmds_ddr_out.vhd` (board), two descriptions of the same entity. The board register uses the `altddio_out` megafunction, which Quartus requires from the `altera_mf` library.

## 7. Verification

The encoder test compares the 256 bytes in sequence and a random stream with blanking against a reference model written separately, and checks that each decoded symbol returns the byte, with the running disparity bounded. The serializer test checks that each symbol leaves whole, from bit 0 to bit 9, in input order, and the transmitter test recovers the symbols of the three channels from the pins, aligned by the clock channel, and compares them with the model, including HS and VS on the blue channel. The formal proof of the encoder checks that the decoded symbol is the byte, that the blanking symbol is the one of the pair $C_1 C_0$, that the running disparity is the sum of the symbols sent and that its modulus never exceeds 8, with mutants it must reject.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
