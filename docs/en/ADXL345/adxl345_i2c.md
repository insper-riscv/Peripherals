# ADXL345 accelerometer controller over I2C (DE0-Nano and DE10-Lite)

🌐 [Português](../../pt-br/ADXL345/adxl345_i2c.md) · [English](../../en/ADXL345/adxl345_i2c.md)

## 1. What it is

Bus controller of the ADXL345 three-axis accelerometer over I2C (`adxl345_i2c`), sibling of the SPI controller described in `adxl345.md` and with the same register map. When enabled, it configures the chip (rate, range, resolution and data-ready interrupt) and then reads, at fixed intervals or on each data-ready signal on INT1 or INT2, the six bytes of the X, Y and Z axes. Each axis becomes a 32-bit register holding the 16-bit two's complement value sign-extended. The chip enters I2C with the chip select at a high level, and the controller keeps it at 1 on `o_adxl_cs_n`.

| Block | Role |
| :--- | :--- |
| `i2c_core` | Line state machine of the I2C master, with start, repeated start, stop and clock stretching |
| `adxl345_i2c` | Command sequencer, axis registers, timing and interrupt |
| `adxl345_consts` | Chip register addresses, configuration values and the 7-bit slave addresses |

## 2. Pins and boards

### 2.1. DE0-Nano

The manual (section 3.7, table 3-10) wires the ADXL345 to the `I2C_SCLK` and `I2C_SDAT` lines, which it shares with the EEPROM, to `G_SENSOR_CS_N` and to `G_SENSOR_INT`. Section 3.4 of the manual gives the EEPROM addresses 0xA0 and 0xA1, which do not clash with the accelerometer ones.

| Port | Function | Name in the manual | FPGA pin |
| :--- | :--- | :--- | :--- |
| `o_adxl_scl_low` and `i_adxl_scl` | SCL | `I2C_SCLK` | `PIN_F2` |
| `o_adxl_sda_low` and `i_adxl_sda` | SDA | `I2C_SDAT` | `PIN_F1` |
| `o_adxl_cs_n` | Chip select, at 1 for I2C | `G_SENSOR_CS_N` | `PIN_G5` |
| `i_adxl_int1` | Interrupt | `G_SENSOR_INT` | `PIN_M2` |

The DE0-Nano manual does not give the chip address. The `o_adxl_sdo` and `i_adxl_int2` pins stay unconnected on that board.

### 2.2. DE10-Lite

The manual (section 3.10, table 3-13) says that, with `GSENSOR_CS_n` at a high level, the chip is in I2C, and that the `GSENSOR_SDO` pin at a high level gives the 7-bit address 0x1D and at a low level the address 0x53. In this mode `GSENSOR_SDI` is the serial data (SDA) and `GSENSOR_SCLK` the clock (SCL). SDO is an FPGA pin, so the controller drives it with `o_adxl_sdo`.

| Port | Function | Name in the manual | FPGA pin |
| :--- | :--- | :--- | :--- |
| `o_adxl_scl_low` and `i_adxl_scl` | SCL | `GSENSOR_SCLK` | `PIN_AB15` |
| `o_adxl_sda_low` and `i_adxl_sda` | SDA | `GSENSOR_SDI` | `PIN_V11` |
| `o_adxl_sdo` | Address select | `GSENSOR_SDO` | `PIN_V12` |
| `o_adxl_cs_n` | Chip select, at 1 for I2C | `GSENSOR_CS_n` | `PIN_AB16` |
| `i_adxl_int1` | Interrupt 1 | `GSENSOR_INT1` | `PIN_Y14` |
| `i_adxl_int2` | Interrupt 2 | `GSENSOR_INT2` | `PIN_Y13` |

All at 3.3 V LVTTL. The SCL and SDA lines are open drain. The platform top wires a tristate to each one (driving 0 when `o_adxl_*_low` is 1 and high impedance when it is 0), returns the pin level on `i_adxl_scl` and `i_adxl_sda`, and the lines need a pull-up.

## 3. Parameters and ports

| Parameter | Default | Meaning |
| :--- | ---: | :--- |
| `clock_hz` | 50000000 | Module clock frequency, in hertz |
| `scl_hz` | 100000 | SCL frequency after reset, in hertz |
| `sample_hz` | 100 | Samples per second after reset, when the interval is timed |
| `bus_free_ns` | 1300 | Minimum interval between a stop and the next start, in nanoseconds |
| `address_select_high` | false | True with SDO at a high level (address 0x1D); false with SDO at a low level (0x53) |

The reset divider is $\lceil clock\_hz / (5 \cdot scl\_hz) \rceil - 1$, never below 2, and the reset interval between samples is $clock\_hz / sample\_hz$ cycles. The bus ports are `i_clk`, `i_rst`, `i_write`, `i_address` (3 bits), `i_data_in`, `o_data_out` and `o_irq`, plus the pins of section 2. The window takes 8 words and a read has no side effect.

## 4. Sequence

With `ENABLE` at 1, and after any write to `CONTROL`, the controller repeats the configuration, and the chip only measures after the last step.

| Step | Transaction | Effect |
| ---: | :--- | :--- |
| 1 | read of `DEVID` (0x00), one byte | The byte read goes to the `DEVID` register |
| 2 | write of `BW_RATE` (0x2C) | Rate code of `RATE` |
| 3 | write of `DATA_FORMAT` (0x31) | `FULL_RES` and `RANGE` |
| 4 | write of `INT_MAP` (0x2F) | Data ready on INT1 (`INT_PIN` at 0) or on INT2 |
| 5 | write of `INT_ENABLE` (0x2E) | 0x80, data ready |
| 6 | write of `POWER_CTL` (0x2D) | 0x08, measurement |
| 7 | burst read from `DATAX0` (0x32), six bytes | X, Y and Z, low byte first |

A register write is start, slave address with write, register address, value and stop. A read is start, address with write, register address, repeated start, address with read, the bytes read with ACK and the last with NACK, and stop. The burst read repeats every `PERIOD` cycles or, with `USE_INT`, while the pin picked by `INT_PIN` is at a high level.

A NACK from the slave or a lost arbitration ends the sequence. The controller releases the lines (with a stop, if the command that got the NACK did not carry one), raises `NACK` or `ARB_LOST` in `STATUS` and returns to idle until the next write to `CONTROL`.

### 4.1. Origin of each parameter

The ADXL345 datasheet is not in the repository, so only what the manuals say is confirmed.

| Item | Origin |
| :--- | :--- |
| Pins, 2-wire I2C, CS high equals I2C, addresses 0x1D and 0x53 by SDO, INT1 and INT2 | Confirmed by the manuals (DE0-Nano section 3.7, DE10-Lite section 3.10) |
| Addresses 0x00, 0x2C, 0x2D, 0x2E, 0x2F, 0x31 and 0x32 to 0x37 and their values, register pointer with automatic increment | Not confirmed; from the datasheet, from memory |
| `DEVID` equal to 0xE5 | Not confirmed; the controller only stores the byte read |
| SCL up to 400 kHz and minimum interval between stop and start | Not confirmed; the controller uses conservative values |

## 5. Registers

| Word | Name | Access | Reset | Description |
| ---: | :--- | :--- | ---: | :--- |
| 0 | `X` | R | 0 | X axis, 16 bits in two's complement sign-extended |
| 1 | `Y` | R | 0 | Y axis |
| 2 | `Z` | R | 0 | Z axis |
| 3 | `STATUS` | R/W1C | 0 | State and flags (table below) |
| 4 | `CONTROL` | R/W | `0xA00` | Enable, interrupt, range, resolution, trigger, pin and rate |
| 5 | `PERIOD` | R/W | section 3 | Bits 23:0, cycles between samples without `USE_INT` |
| 6 | `DEVID` | R | 0 | Bits 7:0, last `DEVID` read |
| 7 | `DIVIDER` | R/W | section 3 | Bits 15:0, SCL clock divider, minimum 2 |

| `STATUS` bit | Name | Access | Meaning |
| ---: | :--- | :--- | :--- |
| 0 | `BUSY` | R | A transaction is in progress |
| 1 | `SAMPLE` | W1C | A new sample was read; a new event beats the clear |
| 2 | `VALID` | R | A sample has arrived since reset |
| 3 | `CONFIGURED` | R | The configuration finished |
| 4 | `NACK` | W1C | The slave did not answer with ACK |
| 5 | `ARB_LOST` | W1C | The controller lost the arbitration |
| 6 | `INT1` | R | Synchronized level of the INT1 pin |
| 7 | `INT2` | R | Synchronized level of the INT2 pin |

| `CONTROL` bit | Name | Meaning |
| ---: | :--- | :--- |
| 0 | `ENABLE` | Turns on the configuration and the periodic read |
| 1 | `IRQ_ENABLE` | Interrupt while `SAMPLE` is 1 |
| 3:2 | `RANGE` | Range, 0 to 3 for 2, 4, 8 and 16 g |
| 4 | `FULL_RES` | Full resolution |
| 5 | `USE_INT` | The read waits for the interrupt pin at a high level instead of the timer |
| 6 | `INT_PIN` | Data-ready pin, 0 for INT1 and 1 for INT2 |
| 11:8 | `RATE` | Rate code written to `BW_RATE` (reset 0xA) |

The `o_irq` output is level-type and equals `SAMPLE` with `IRQ_ENABLE`. A write to `CONTROL` redoes the configuration, and a write to `PERIOD` or `DIVIDER` takes effect from the next transaction.

## 6. Verification

The entity test wires the controller to an ADXL345 model on I2C, with a register pointer, a register file and the INT1 and INT2 pins, and runs with SDO at a low level and at a high level. The cases cover the reset values and the pins at rest, the configuration sequence with the requested range and rate and the start and stop counts of the bus, the periodic read with negative and positive 13-bit axes and 1 g on the Z axis, the read triggered by INT1 and by INT2, the interrupt, the reconfiguration through `CONTROL` and the NACK of an absent slave, with the lines released and the recovery after the fix. The model repeats the assumptions of section 4.1, marked in the code. Reading 1 g on the Z axis with the board at rest depends on a bench test.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
