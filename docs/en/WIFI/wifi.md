# NINA Wi-Fi module bridge

🌐 [Português](../../pt-br/WIFI/wifi.md) · [English](../../en/WIFI/wifi.md)

## 1. Reference

The Arduino MKR Vidor 4000 (ABX00022) has the u-blox NINA-W102 Wi-Fi and Bluetooth module, based on the ESP32, wired to the 10CL016YU256C8G FPGA through the `WM_*` pins. The number of each `WM_PIO` net is that of the module pin. The pins come from the board catalog of Insper-RISC-V (`boards/mkr-vidor-4000/pins.yaml`), read from the pin file of the Arduino reference project (`vidor_s_pins.qsf`, VidorBitstream) and checked against the ABX00022 schematic and the board datasheet.

| Board signal | FPGA pin | I/O standard | Function on the module | Bridge port |
| :--- | :--- | :--- | :--- | :--- |
| `oWM_RESET` | R1 | 2.5 V | Module reset (active low) | `o_wm_reset_n` |
| `bWM_PIO27` | N9 | 3.3 V LVTTL | ESP32 GPIO0 (boot select) | `o_wm_gpio0`, `o_wm_gpio0_oe` |
| `bWM_PIO7` | P6 | 3.3 V LVTTL | ESP32 GPIO33 (SPI ready, ACK) | `i_wm_ack` |
| `bWM_PIO29` | T10 | 3.3 V LVTTL | SPI clock (GPIO18) | `o_wm_sck` |
| `bWM_PIO36` | N1 | 2.5 V | SPI COPI (GPIO12) | `o_wm_copi` |
| `bWM_PIO1` | T11 | 3.3 V LVTTL | SPI CIPO (GPIO23) | `i_wm_cipo` |
| `bWM_PIO28` | N11 | 3.3 V LVTTL | SPI select (GPIO5) | `o_wm_cs_n` |
| `iWM_TX` | E15 | 3.3 V LVTTL | Serial output of the module (GPIO1) | `i_wm_tx` |
| `oWM_RX` | T6 | 3.3 V LVTTL | Serial input of the module (GPIO3) | `o_wm_rx` |
| `bWM_PIO20` | R5 | 3.3 V LVTTL | Module RTS | `i_wm_rts` |
| `bWM_PIO21` | R6 | 3.3 V LVTTL | Module CTS | `o_wm_cts` |

The mapping of pins to ESP32 functions comes from the Arduino reference project, which wires the SPI and the UART of the board SAMD21 microcontroller to the module through these same pins. The Wi-Fi co-processor firmware of the module (`nina-fw`, by Arduino) works as an SPI slave in mode 0, keeps the ready pin high while free and takes it low during an exchange, and speaks 115200 baud on its console UART. The ESP32 enters firmware download mode when GPIO0 is low as reset ends. The reset polarity (active low) and the RTS and CTS pair on `WM_PIO20` and `WM_PIO21` (names `iWM_RTS` and `iWM_CTS` in the pin file) are assumptions not confirmed on the bench.

## 2. What it is

The bridge gives the processor, in a single register window, everything the FPGA wires to the module. The module runs one firmware at a time, and the bridge offers the two paths it uses, the SPI of the co-processor firmware and the UART of the firmware loader and of the AT commands, so the software picks one of them.

| Block | Instance | Function |
| :--- | :--- | :--- |
| Control | `wifi_regs` | Module reset, boot select (GPIO0) and the ACK input with an interrupt |
| SPI | `spi` (SPI master of the repository) | SPI master with one select line and transmit and receive queues |
| UART | `uart` (UART of the repository) | 8N1 UART with queues and, optionally, RTS and CTS flow control |

The `wifi` top only decodes the address, picks the read data and adds the interrupts. The SPI and UART registers are those of the [SPI](../SPI/spi.md) and [UART](../UART/serial_uart.md) documents.

| Generic | Default | Meaning |
| :--- | :--- | :--- |
| `clock_hz` | 50000000 | System clock frequency in Hz; the reset pulse and the SPI reset divider derive from it |
| `reset_pulse_ms` | 10 | Duration of the module reset pulse in milliseconds |
| `run_at_reset` | `false` | Module out of reset right after the system reset |
| `spi_reset_sclk_hz` | 1000000 | SPI SCLK frequency after reset, in Hz |
| `spi_rx_fifo_depth`, `spi_tx_fifo_depth` | 16 | Words of the SPI queues |
| `uart_baud_freq`, `uart_baud_limit` | `0x240`, `0x3AC9` | Baud generator constants (115200 baud at 50 MHz) |
| `uart_rx_fifo_depth`, `uart_tx_fifo_depth` | 16 | Bytes of the UART queues |
| `has_flow_control` | `false` | Includes RTS and CTS flow control in the UART |

## 3. Interface

| Port | Direction | Function |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | System clock and synchronous reset, active at 1 |
| `i_write`, `i_read` | input | Write and read pulses of the processor |
| `i_address` | input | 5-bit word address |
| `i_data_in`, `o_data_out` | input, output | Write and read data (`word_t`) |
| `o_irq` | output | Level interrupt, active at 1 |
| `o_wm_reset_n` | output | Module reset, active at 0 |
| `o_wm_gpio0`, `o_wm_gpio0_oe` | output | Value (always 0) and driver enable of GPIO0; the platform puts the pin in high impedance when the enable is 0 |
| `i_wm_ack` | input | Module ACK, asynchronous; goes through a two-stage synchronizer |
| `o_wm_sck`, `o_wm_copi`, `i_wm_cipo`, `o_wm_cs_n` | output, output, input, output | SPI to the module; the select is active at 0 |
| `i_wm_tx`, `o_wm_rx` | input, output | UART to the module; `i_wm_tx` is the serial output of the module |
| `i_wm_rts`, `o_wm_cts` | input, output | Flow control, active at 0; valid only with `has_flow_control` |

## 4. Address map

Accesses are 32 bits wide, and the address is a word address. An address outside the map reads zero and ignores writes.

| Addresses | Block | Registers |
| :--- | :--- | :--- |
| 0x00 to 0x02 | Control | `CTRL`, `STATUS`, `RESET_PULSE` |
| 0x08 to 0x0D | SPI | `TX_DATA`, `RX_DATA`, `STATUS`, `CONTROL`, `DIVIDER`, `TX_LISTEN` |
| 0x10 to 0x13 | UART | `TX_DATA`, `RX_DATA`, `STATUS`, `CONTROL` |

## 5. Control block

### 5.1. `CTRL` (address 0x00, read and write)

| Bit | Name | Description |
| :--- | :--- | :--- |
| 0 | `RUN` | Releases the module reset; at 0, the module stays in reset (reset value, unless `run_at_reset` is `true`) |
| 1 | `BOOT_LOW` | Pulls the module GPIO0 low (firmware download mode); at 0, the pin is in high impedance |
| 2 | `RISE_IE` | Interrupt while `RISE` is 1 |
| 3 | `FALL_IE` | Interrupt while `FALL` is 1 |

### 5.2. `STATUS` (address 0x01)

| Bit | Name | Description |
| :--- | :--- | :--- |
| 0 | `ACK` | Synchronized level of the ACK pin |
| 1 | `RISE` | ACK had a rising edge; stays at 1 until 1 is written to the bit |
| 2 | `FALL` | ACK had a falling edge; stays at 1 until 1 is written to the bit |
| 3 | `PULSE` | Reset pulse in progress (read only) |

### 5.3. `RESET_PULSE` (address 0x02)

Writing 1 to bit 0 holds `o_wm_reset_n` at 0 for $reset\_pulse\_ms$ milliseconds and returns it to the value of `RUN`. Bit 0 reads 1 while the pulse runs, and writing 1 during the pulse restarts it. With `RUN` at 0, the pulse changes nothing on the pin, which is already 0.

$$o\_wm\_reset\_n = RUN \wedge \neg PULSE$$

## 6. Usage sequences

### 6.1. Normal boot

| Step | Action |
| :--- | :--- |
| 1 | Write `CTRL` with `RUN` at 1 and `BOOT_LOW` at 0 |
| 2 | Wait for the module to start its firmware; with the co-processor firmware, the ACK pin stays high while the module is free |

### 6.2. Firmware download mode

| Step | Action |
| :--- | :--- |
| 1 | Write `CTRL` with `BOOT_LOW` at 1 and `RUN` at 0 |
| 2 | Write `CTRL` with `BOOT_LOW` at 1 and `RUN` at 1, or write 1 to `RESET_PULSE` |
| 3 | Flash the firmware through the UART with the ESP32 loader protocol |
| 4 | Write `CTRL` with `BOOT_LOW` at 0 and repeat step 2 of the normal boot |

### 6.3. SPI exchange

The reset SPI is already 8 bits in mode 0, which is the mode of the co-processor firmware. The software writes `CS_ASSERT` to the SPI `CONTROL`, queues the bytes of a command in `TX_DATA` and reads the answers from `RX_DATA`. The firmware takes the ACK pin low during an exchange and returns it high when it ends, so `RISE` indicates a ready module, and the `RISE_IE` interrupt tells the processor without polling.

## 7. Interrupt

$$o\_irq = (RISE\_IE \wedge RISE) \vee (FALL\_IE \wedge FALL) \vee irq_{SPI} \vee irq_{UART}$$

The output is a level. The first two terms drop when the software writes 1 to the matching bit of `STATUS`, and the other two follow the masks of the SPI and of the UART.

## 8. Limits

| Item | Situation |
| :--- | :--- |
| Pass-through bridge to the SAMD21 | Not part of the peripheral; the platform closes it outside, through the `bMKR_*` pins, when it needs it |
| I2C pins of the module (`bWM_PIO35` and `bWM_PIO31`) and the other `bWM_PIO` | Not used by the bridge |
| Module protocol | The bridge moves bytes and drives the pins; the command protocol of the firmware belongs to the software |
| Electrical and timing values | The 10 ms reset pulse, the RTS and CTS on `WM_PIO20` and `WM_PIO21` and the 2.5 V levels of `oWM_RESET` and `bWM_PIO36` follow the pin file and were not checked on the bench |

## 9. C example

The program takes the module out of reset and waits for the ACK pin to rise. The window base comes from the header generated from `platform.yaml`.

```c
#include <stdint.h>

enum { WIFI_CTRL = 0, WIFI_STATUS = 1, WIFI_RESET_PULSE = 2 };

enum : uint32_t {
    CTRL_RUN = 1u << 0,
    STAT_ACK = 1u << 0,
};

void wifi_boot(volatile uint32_t *wifi) {
    wifi[WIFI_CTRL] = CTRL_RUN;
    while (!(wifi[WIFI_STATUS] & STAT_ACK)) {
    }
}
```

## 10. Verification

The entity tests cover the control block (reset, `RUN`, `BOOT_LOW`, reset pulse with the duration of the generic, ACK edges, masks and clearing) and the full block (address map without overlap and with empty addresses reading zero, reset pulse with the millisecond generic, SPI byte exchange with a simulated slave in mode 0, UART frame in both directions and the sum of the interrupts). The SPI and UART tests are those of their own peripherals. The tests are simulations, and the bridge was not exercised with a real module. The formal verification flow of the repository has no proofs for this bridge.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
