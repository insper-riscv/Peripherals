# I2C Master

🌐 [Português](../../pt-br/I2C/i2c_master.md) · [English](../../en/I2C/i2c_master.md)

## 1. What it is

A general-purpose I2C master (`i2c_master`) for a two-wire bus, SCL and SDA, with open-drain pins. It serves any slave on the bus, and on the DE2-115 it serves the 32 Kbit EEPROM, the WM8731 audio codec and the ADV7180 TV decoder. The processor writes one command per bus action (start, stop, send or receive one byte) and follows the end through the busy bit or the interrupt.

The master generates the start, repeated start and stop conditions, sends and receives bytes with the ACK phase, waits for a slave that stretches the clock, detects lost arbitration and flags the NACK. There is no FIFO: a command register and a busy bit give a one-byte-at-a-time interface that is simple to use in a polling loop and easy to prove.

## 2. Interface

### 2.1. Generics

| Generic | Default | Description |
| :--- | ---: | :--- |
| `clk_freq` | 100000000 | Frequency of `i_clk` in Hz |
| `scl_freq` | 100000 | SCL frequency in Hz that the divider has out of reset; 400000 gives fast mode |

### 2.2. Ports

| Port | Direction | Description |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | Clock and synchronous reset, active high |
| `i_write`, `i_read` | input | Bus write and read strobes |
| `i_address` | input, 3 bits | Register word address |
| `i_data_in`, `o_data_out` | input and output, `word_t` | Bus data; the output is zero outside a read |
| `o_irq` | output | Level interrupt |
| `o_scl_low`, `o_sda_low` | output | Are 1 when the master pulls the line low |
| `i_scl`, `i_sda` | input | Level read from each pin, synchronized by two flip-flops inside the block |

## 3. Registers

The address is a 3-bit word address. An address outside the table reads zero and ignores writes.

| Word | Name | Access | Reset | Description |
| ---: | :--- | :--- | :--- | :--- |
| 0 | `CTRL` | read and write | 0 | Bit 0 `ENABLE`, bit 1 `IRQ_DONE`, bit 2 `IRQ_ERR`; bit 3 `ABORT` is a write pulse and reads as zero |
| 1 | `DIVIDER` | read and write | Computed from the generics | 16-bit divider; values below 2 are stored as 2 |
| 2 | `CMD` | write | not applicable | Command; reads zero |
| 3 | `TX` | read and write | 0 | Byte the next send command transmits |
| 4 | `RX` | read | 0 | Last byte received |
| 5 | `STATUS` | read and write 1 to clear | 0 | State, see the bit table |

### 3.1. `CMD` bits

A command performs, in this order, the start, the byte and the stop that its bits ask for.

| Bit | Name | Effect |
| ---: | :--- | :--- |
| 0 | `START` | Generates a start (or a repeated start if the master already has the transaction open) |
| 1 | `STOP` | Generates a stop at the end of the command |
| 2 | `READ` | Receives a byte into `RX` |
| 3 | `WRITE` | Sends the byte of `TX` |
| 4 | `NACK` | With `READ`, answers NACK to the received byte; with 0, answers ACK |

A command is refused, without touching the bus and with the `REJECTED` bit set, when the master is off or busy, when it carries no action bit, when it asks for `READ` and `WRITE` together, or when it has no `START` and no transaction is open.

### 3.2. `STATUS` bits

| Bit | Name | Description |
| ---: | :--- | :--- |
| 0 | `BUSY` | Command in execution |
| 1 | `BUS_ACTIVE` | The master gave a start and has not given the stop yet |
| 2 | `DONE` | Command finished, also by lost arbitration; stays set until cleared |
| 3 | `NACK` | The byte sent, address or data, got a NACK; stays set until cleared |
| 4 | `ARB_LOST` | The master lost arbitration; stays set until cleared |
| 5 | `REJECTED` | A command was refused; stays set until cleared |

Writing 1 to one of bits 2 to 5 clears that bit. An event in the same cycle as the write wins. When `BUSY` returns to 0, `DONE` is already 1.

## 4. Behavior

### 4.1. Timing

Each SCL bit lasts five steps, three with SCL low and two with SCL high, and one step lasts `DIVIDER + 1` cycles of `i_clk`:

$$ f_{scl} = \frac{f_{clk}}{5 \cdot (DIVIDER + 1)} $$

With `clk_freq` of 100 MHz, the reset divider is 199 for 100 kHz and 49 for 400 kHz. The 3 to 2 ratio between SCL low and high meets the minimum times of both speeds. Start and stop use more steps (SCL high for three steps before SDA falls, and SDA released for one step after the stop), which respects the setup and hold times of standard mode.

The minimum divider is 2, which gives three cycles per step and lets the pin reading cross the synchronizer before it is sampled. On real hardware, choose the divider so that one step is much longer than the rise time of the line.

### 4.2. Clock stretching

After releasing SCL, the master only advances when it reads SCL as 1, and it stays put while the slave holds it at 0. If the slave never releases it, the command does not end; software leaves that situation by writing `ABORT` in `CTRL`, which releases both lines and cancels the command.

### 4.3. Arbitration and NACK

The master checks SDA when it releases the line. It loses arbitration when it sends a 1 bit and reads SDA as 0, or when it releases SDA before a start or a stop and reads 0. It then releases both lines, ends the command and sets `ARB_LOST` and `DONE`. A sent byte whose ACK bit reads 1 sets `NACK`, and the command goes on to the end, including the requested stop.

### 4.4. Interrupt

$$ o\_irq = (DONE \cdot IRQ\_DONE) + (NACK + ARB\_LOST + REJECTED) \cdot IRQ\_ERR $$

The output is a level and drops when software clears the `STATUS` bits.

## 5. Pin connection

The block delivers only `o_scl_low`, `o_sda_low`, `i_scl` and `i_sda`. The platform top connects the tri-state buffer of each line, which drives 0 when `o_*_low` is 1 and is high impedance when it is 0, and returns the pin level on `i_scl` and `i_sda`. The lines need an external pull-up resistor or one on the pin.

| Board | Bus | Manual pins | Slaves |
| :--- | :--- | :--- | :--- |
| DE2-115 | EEPROM | `EEP_I2C_SCLK` (PIN_D14) and `EEP_I2C_SDAT` (PIN_E14) | 32 Kbit EEPROM, address 0xA0 for write and 0xA1 for read |
| DE2-115 | Audio and video | `I2C_SCLK` (PIN_B7) and `I2C_SDAT` (PIN_A8) | WM8731 codec and ADV7180 decoder, which share the same bus |

The DE0-CV has no I2C bus on the pins of its manual. The two buses of the DE2-115 are independent and take one `i2c_master` instance each.

## 6. Reading and writing an EEPROM

### 6.1. Family parameters

| Capacity | Byte address | Note |
| :--- | :--- | :--- |
| 2 Kbit (256 bytes) | 1 byte | |
| 4 Kbit to 16 Kbit | 1 byte | The high address bits enter the device address bits, see the chip datasheet |
| 32 Kbit to 64 Kbit | 2 bytes, most significant first | |

The write page size comes from the chip datasheet (a power of two). A write that crosses the page boundary wraps to the start of the page and overwrites bytes. The 7-bit device address is 0x50 on the boards cited (address byte 0xA0 for write and 0xA1 for read).

### 6.2. Sequences

Page write:

1. `TX` receives the device address byte with the write bit and `CMD` receives `START | WRITE`.
2. For each address byte (one or two), `TX` receives the byte and `CMD` receives `WRITE`.
3. For each data byte, `TX` receives the byte and `CMD` receives `WRITE`, and the last one carries `WRITE | STOP`.
4. Wait for the internal write cycle by ACK polling, repeating `START | WRITE | STOP` with the device address byte until the byte is accepted (no `NACK`). While the chip writes, it answers NACK to its address.

Random read:

1. `START | WRITE` with the write address byte, and the address bytes with `WRITE`, without `STOP`.
2. `START | WRITE` with the read address byte (repeated start).
3. For each byte, `CMD` receives `READ`, the byte comes out of `RX`, and the last byte carries `READ | NACK | STOP`.

### 6.3. C example

```c
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define I2C_BASE       0x10002000u  /* base of the peripheral window on the platform */
#define I2C_REG(n)     (*(volatile uint32_t *)(I2C_BASE + 4u * (n)))
#define I2C_CTRL       I2C_REG(0)
#define I2C_DIVIDER    I2C_REG(1)
#define I2C_CMD        I2C_REG(2)
#define I2C_TX         I2C_REG(3)
#define I2C_RX         I2C_REG(4)
#define I2C_STATUS     I2C_REG(5)

#define CTRL_ENABLE    (1u << 0)
#define CMD_START      (1u << 0)
#define CMD_STOP       (1u << 1)
#define CMD_READ       (1u << 2)
#define CMD_WRITE      (1u << 3)
#define CMD_NACK       (1u << 4)
#define ST_BUSY        (1u << 0)
#define ST_NACK        (1u << 3)
#define ST_ARB_LOST    (1u << 4)
#define ST_REJECTED    (1u << 5)

#define EEPROM_WRITE   0xA0u
#define EEPROM_READ    0xA1u
#define EEPROM_TWO_ADDRESS_BYTES true   /* 32 Kbit to 64 Kbit; false for 2 Kbit */
#define POLL_TRIES     1000u

/* Waits for the end of the command and returns the status. */
static uint32_t i2c_wait(void) {
    uint32_t status;
    do {
        status = I2C_STATUS;
    } while (status & ST_BUSY);
    return status;
}

/* Runs a send command and tells whether the slave answered ACK. */
static bool i2c_send(uint32_t flags, uint8_t byte) {
    I2C_STATUS = ST_NACK | ST_ARB_LOST | ST_REJECTED;
    I2C_TX = byte;
    I2C_CMD = flags | CMD_WRITE;
    return (i2c_wait() & (ST_NACK | ST_ARB_LOST | ST_REJECTED)) == 0;
}

void i2c_init(void) {
    I2C_CTRL = CTRL_ENABLE;          /* 100 kHz with the reset divider */
}

/* Sends the device address and the byte address, without a stop. */
static bool eeprom_set_address(uint16_t address) {
    bool ok = i2c_send(CMD_START, EEPROM_WRITE);
    if (EEPROM_TWO_ADDRESS_BYTES) {
        ok = ok && i2c_send(0, (uint8_t)(address >> 8));
    }
    return ok && i2c_send(0, (uint8_t)address);
}

/* Waits for the write cycle by ACK polling. */
static bool eeprom_wait_ready(void) {
    for (uint32_t i = 0; i < POLL_TRIES; i++) {
        bool ready = i2c_send(CMD_START | CMD_STOP, EEPROM_WRITE);
        if (ready) {
            return true;
        }
    }
    return false;
}

/* Writes up to one page; the caller does not cross the page boundary. */
bool eeprom_write_page(uint16_t address, const uint8_t *data, size_t length) {
    if (length == 0) {
        return false;
    }
    bool ok = eeprom_set_address(address);
    for (size_t i = 0; ok && i < length; i++) {
        ok = i2c_send(i + 1 == length ? CMD_STOP : 0, data[i]);
    }
    if (!ok) {
        I2C_CMD = CMD_STOP;
        i2c_wait();
        return false;
    }
    return eeprom_wait_ready();
}

/* Random read of length bytes from address. */
bool eeprom_read(uint16_t address, uint8_t *data, size_t length) {
    if (!eeprom_set_address(address) || !i2c_send(CMD_START, EEPROM_READ)) {
        I2C_CMD = CMD_STOP;
        i2c_wait();
        return false;
    }
    for (size_t i = 0; i < length; i++) {
        bool last = i + 1 == length;
        I2C_CMD = CMD_READ | (last ? (CMD_NACK | CMD_STOP) : 0u);
        i2c_wait();
        data[i] = (uint8_t)I2C_RX;
    }
    return true;
}
```

In the polling, the command carries `START` and `STOP` together, so the stop is sent even when the chip refuses the address.

## 7. Verification

The entity tests run the master against a behavioral EEPROM model in Python, with 1-byte and 2-byte addressing, page write wrapping to the start of the page, a write cycle with NACK, clock stretching and a second master that wins arbitration. They cover the SCL period, the start, repeated start and stop conditions, the address NACK, the refusal of commands, the abort, the interrupts and the reset divider for each frequency. The formal proof checks the registers, the reads, the interrupt and the release of the lines of the top, and the done pulse, the lines and the arbitration of the line state machine, with mutants of each.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
