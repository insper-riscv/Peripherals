# ADXL345 accelerometer controller over SPI (DE0-Nano and DE10-Lite)

🌐 [Português](../../pt-br/ADXL345/adxl345.md) · [English](../../en/ADXL345/adxl345.md)

## 1. What it is

Bus controller of the ADXL345 three-axis accelerometer over SPI. When enabled, it configures the chip (rate, range, resolution and data-ready interrupt) and then reads, at fixed intervals or on each data-ready signal on INT1, the six bytes of the X, Y and Z axes. Each axis becomes a 32-bit register holding the 16-bit two's complement value sign-extended (13 useful bits at the 16 g range with full resolution). The chip also speaks I2C, and that access is done by software with the I2C master of the repository, without going through this controller.

| Block | Role |
| :--- | :--- |
| `spi_master` | One-word SPI master, here in mode 3 with 8-bit words |
| `adxl345` | Configuration and burst-read sequencer, axis registers, timing and interrupt |

## 2. Pins and boards

### 2.1. DE0-Nano

The manual (section 3.7, table 3-10) wires the ADXL345 to the lines I2C_SCLK and I2C_SDAT (shared with the EEPROM, which the table describes as "EEPROM clock" and "EEPROM data"), to G_SENSOR_CS_N and to G_SENSOR_INT. The manual says the chip is accessed through 3-wire SPI or through I2C, so SPI on this board is the three-wire one, with data going both ways on the same pin.

| Peripheral port | Role in three-wire SPI | Name in the manual | FPGA pin |
| :--- | :--- | :--- | :--- |
| `o_adxl_sclk` | SCLK | `I2C_SCLK` | `PIN_F2` |
| `o_adxl_mosi` and `o_adxl_mosi_oe` with `i_adxl_miso` | SDIO, bidirectional | `I2C_SDAT` | `PIN_F1` |
| `o_adxl_cs_n` | Chip select | `G_SENSOR_CS_N` | `PIN_G5` |
| `i_adxl_int1` | Data-ready interrupt | `G_SENSOR_INT` | `PIN_M2` |

All at 3.3 V. The bidirectional pin is built in the platform top, driven with `o_adxl_mosi` when `o_adxl_mosi_oe` is 1 and high impedance otherwise, and `i_adxl_miso` reads the pin itself. The manual does not give the I2C address of the chip on this board.

### 2.2. DE10-Lite

The manual (section 3.10, table 3-13) lists the six pins. With GSENSOR_CS_n high the chip is in I2C mode, and with it low in SPI mode. Section 5.5 of the manual uses three-wire SPI and sets the SPI bit of register 0x31 (`DATA_FORMAT`) before reading. The manual describes the outputs as 16-bit two's complement.

| Peripheral port | Role | Name in the manual | FPGA pin |
| :--- | :--- | :--- | :--- |
| `o_adxl_sclk` | SCLK (3-wire and 4-wire SPI) | `GSENSOR_SCLK` | `PIN_AB15` |
| `o_adxl_mosi` | SDI in 4-wire; SDIO in 3-wire | `GSENSOR_SDI` | `PIN_V11` |
| `i_adxl_miso` | SDO in 4-wire | `GSENSOR_SDO` | `PIN_V12` |
| `o_adxl_cs_n` | Chip select | `GSENSOR_CS_n` | `PIN_AB16` |
| `i_adxl_int1` | Interrupt 1 | `GSENSOR_INT1` | `PIN_Y14` |
| none | Interrupt 2 | `GSENSOR_INT2` | `PIN_Y13` |

All at 3.3 V LVTTL. In I2C the manual gives the 7-bit address 0x1D with GSENSOR_SDO high and 0x53 with it low (0x3A and 0x3B, or 0xA6 and 0xA7, with the write or read bit). With the `three_wire` parameter true the controller sets the SPI bit and the platform must wire `i_adxl_miso` to the SDI pin; with it false it uses four wires, and `i_adxl_miso` reads SDO.

## 3. Parameters and ports

| Parameter | Default | Meaning |
| :--- | ---: | :--- |
| `clock_hz` | 50000000 | Module clock frequency, in hertz |
| `sclk_hz` | 1000000 | SCLK frequency after reset, in hertz |
| `sample_hz` | 100 | Samples per second after reset, when the interval is timed |
| `cs_high_ns` | 300 | Minimum time with the chip select high, in nanoseconds |
| `three_wire` | true | True with the shared data line (sets the SPI bit of `DATA_FORMAT`) |

The reset divider is $\lceil clock\_hz / (2 \cdot sclk\_hz) \rceil - 1$, and the reset interval between samples is $clock\_hz / sample\_hz$ cycles. The bus ports are `i_clk`, `i_rst`, `i_write`, `i_address` (3 bits), `i_data_in`, `o_data_out` and `o_irq`, plus the pins of section 2 (`o_adxl_cs_n`, `o_adxl_sclk`, `o_adxl_mosi`, `o_adxl_mosi_oe`, `i_adxl_miso` and `i_adxl_int1`). The block window takes 8 words and reads have no side effect.

## 4. Sequence

With `ENABLE` at 1, and after any write to `CONTROL`, the controller repeats the configuration, and the chip only measures after the last step.

| Step | Transaction (command, data) | Effect |
| ---: | :--- | :--- |
| 1 | read of `DEVID` (0x00) | The byte read is kept in the `DEVID` register |
| 2 | write of `BW_RATE` (0x2C) | Rate code from `RATE` |
| 3 | write of `DATA_FORMAT` (0x31) | SPI bit with `three_wire`, `FULL_RES` and `RANGE` |
| 4 | write of `INT_ENABLE` (0x2E) | 0x80, data ready (on INT1 by default) |
| 5 | write of `POWER_CTL` (0x2D) | 0x08, measurement |
| 6 | burst read from `DATAX0` (0x32), command 0xF2 | Six bytes, X, Y and Z, low byte first |

The burst read repeats every `PERIOD` cycles or, with `USE_INT1`, while INT1 is high. Each transaction is a command word and the data words, in mode 3 with the chip select low, and with the shared line the master releases the pin during the six bytes read.

### 4.1. Origin of each parameter

The ADXL345 datasheet is not in the repository, so only what the manual says is confirmed.

| Item | Origin |
| :--- | :--- |
| Pins, 3-wire SPI or I2C, 16-bit two's complement output, CS high selects I2C, SPI bit in register 0x31, I2C addresses | Confirmed by the manuals (DE0-Nano section 3.7, DE10-Lite sections 3.10 and 5.5) |
| Mode 3, command format (read, burst, 6-bit address) | Not confirmed; from the datasheet, from memory |
| Addresses 0x00, 0x2C, 0x2D, 0x2E, 0x31 and 0x32 to 0x37 and their values | Not confirmed; from the datasheet, from memory |
| `DEVID` equal to 0xE5 | Not confirmed; the controller only keeps the byte read |
| SCLK up to 5 MHz, minimum time with CS high, resolution per range | Not confirmed; the controller uses conservative values |

## 5. Registers

| Word | Name | Access | Reset | Description |
| ---: | :--- | :--- | ---: | :--- |
| 0 | `X` | R | 0 | X axis, 16-bit two's complement sign-extended |
| 1 | `Y` | R | 0 | Y axis |
| 2 | `Z` | R | 0 | Z axis |
| 3 | `STATUS` | R/W1C | 0 | State and sample flag (table below) |
| 4 | `CONTROL` | R/W | `0xA00` | Enable, interrupt, range, resolution, trigger and rate |
| 5 | `PERIOD` | R/W | section 3 | Bits 23:0, cycles between samples without `USE_INT1` |
| 6 | `DEVID` | R | 0 | Bits 7:0, last `DEVID` read |
| 7 | `DIVIDER` | R/W | section 3 | Bits 15:0, SCLK clock divider |

| `STATUS` bit | Name | Access | Meaning |
| ---: | :--- | :--- | :--- |
| 0 | `BUSY` | R | A transaction is in progress or requested |
| 1 | `SAMPLE` | W1C | A new sample was read; a new event wins over the clear |
| 2 | `VALID` | R | There has been a sample since reset |
| 3 | `CONFIGURED` | R | The configuration ended |

| `CONTROL` bit | Name | Meaning |
| ---: | :--- | :--- |
| 0 | `ENABLE` | Turns on the configuration and the periodic read |
| 1 | `IRQ_ENABLE` | Interrupt while `SAMPLE` is 1 |
| 3:2 | `RANGE` | Range, 0 to 3 for 2, 4, 8 and 16 g |
| 4 | `FULL_RES` | Full resolution |
| 5 | `USE_INT1` | The read waits for INT1 high instead of the timer |
| 11:8 | `RATE` | Rate code written to `BW_RATE` (reset 0xA) |

The `o_irq` output is level-sensitive and equals `SAMPLE` with `IRQ_ENABLE`. A write to `CONTROL` redoes the configuration, and a write to `PERIOD` or `DIVIDER` takes effect from the next transaction.

## 6. Use by software

The C example enables the controller at the 2 g range with full resolution, waits for the first sample and reads the three axes. The conversion to g uses the factor of 256 LSB per g of the 2 g range at 10 bits, which the chip datasheet gives but the manual does not confirm; with full resolution the factor is about 256 LSB per g at every range, also unconfirmed.

```c
#include <stdint.h>

/* Base of the peripheral, defined by the platform. */
#define ACC_BASE ((volatile uint32_t *)0x40002000u)

enum { X, Y, Z, STATUS, CONTROL, PERIOD, DEVID, DIVIDER };
enum { SAMPLE = 1u << 1, VALID = 1u << 2, CONFIGURED = 1u << 3 };
enum { ENABLE = 1u << 0, FULL_RES = 1u << 4 };

#define RANGE(n) ((uint32_t)(n) << 2)
#define RATE(n) ((uint32_t)(n) << 8)
#define LSB_PER_G 256

/* Turn on the accelerometer at 100 Hz and the 2 g range with full resolution. */
void acc_start(void)
{
    ACC_BASE[CONTROL] = ENABLE | FULL_RES | RANGE(0) | RATE(0xA);
    while ((ACC_BASE[STATUS] & VALID) == 0) {
    }
}

/* Read one axis in thousandths of g (0 = X, 1 = Y, 2 = Z). */
int32_t acc_milli_g(unsigned axis)
{
    return ((int32_t)ACC_BASE[X + axis] * 1000) / LSB_PER_G;
}

/* Wait for a new sample and mark it as read. */
void acc_wait_sample(void)
{
    ACC_BASE[STATUS] = SAMPLE;
    while ((ACC_BASE[STATUS] & SAMPLE) == 0) {
    }
}
```

## 7. Verification

The entity test connects the controller to an ADXL345 model with a register file, command frame, burst and the INT1 pin, and runs with the shared line and with four wires. The cases cover the idle pins, the configuration sequence with the requested range and rate, the periodic read with negative and positive 13-bit axes and 1 g on the Z axis, the read triggered by INT1, the interrupt and the reconfiguration by a write to `CONTROL`. The model flags a conflict on the shared line when the master still drives it during the bytes read and repeats the assumptions of section 4.1, marked in the code. The formal proof checks the five configuration transactions and the burst read in order, with commands, data, byte counts, MOSI driver and chip select gap, and mutants it must reject. Reading 1 g on the Z axis with the board at rest depends on a bench test.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
