# usb_bridge

Memory-mapped peripheral that connects the SoC bus to the 16-bit parallel bus of the board's USB chip. The chip implements USB (host and device); the peripheral only performs read and write accesses to the four ports of the chip, with configurable timing, and reflects the chip interrupts.

## 1. Role of the component in the SoC

Software talks to the chip through 16-bit accesses to four ports, selected by two chip address bits. The peripheral turns each processor read or write into a transaction on the pins (chip select, address, strobe and data) and keeps the data read so the program can fetch it afterwards. No USB stack is part of the peripheral.

### 1.1. Chips and pins

| Board | Chip | Pins in the manual |
| :--- | :--- | :--- |
| DE2-115 (sections 3.5 and 4.17) | Cypress EZ-OTG CY7C67200, HPI interface | `OTG_DATA[15:0]`, `OTG_ADDR[1:0]`, `OTG_CS_N`, `OTG_RD_N`, `OTG_WR_N`, `OTG_RST_N`, `OTG_INT` |

The bridge also serves the ISP1362 of the older DE2 revisions, which has the same data, address and strobe pins, plus the interrupt outputs of the host controller and of the device controller, the DMA request (`OTG_DC_DREQ`) and the DMA acknowledge (`OTG_DC_DACK`). The pins `OTG_FSPEED`, `OTG_LSPEED` and `OTG_RESET` are not part of the bridge.

### 1.2. The four ports

| Chip address (`OTG_ADDR[1:0]`) | Port on the ISP1362 | Port on the HPI interface of the CY7C67200 |
| ---: | :--- | :--- |
| 0 | Host controller data | Data (`HPI_DATA`) |
| 1 | Host controller command | Mailbox (`HPI_MAILBOX`) |
| 2 | Device controller data | Address (`HPI_ADDRESS`) |
| 3 | Device controller command | Status (`HPI_STATUS`) |

The chip address equals the word address of the port in the peripheral (windows 0 to 3 of the register map).

## 2. Registers

The address is the offset in words inside the peripheral (four bits, 64-byte window).

| Word | Name | Access | Reset | Description |
| ---: | :--- | :--- | :--- | :--- |
| 0 | `HC_DATA` | a write requests a write, a read requests a read | a read returns 0 | Chip port 0 |
| 1 | `HC_CMD` | a write requests a write, a read requests a read | a read returns 0 | Chip port 1 |
| 2 | `DC_DATA` | a write requests a write, a read requests a read | a read returns 0 | Chip port 2 |
| 3 | `DC_CMD` | a write requests a write, a read requests a read | a read returns 0 | Chip port 3 |
| 4 | `RDATA` | read | 0 | 16-bit data of the last completed read access; reading it has no side effect |
| 5 | `CTRL` | read and write | 1 | Bit 0 `CHIP_RESET` holds the chip in reset (`OTG_RST_N` low); bit 1 `DACK` drives `OTG_DC_DACK` |
| 6 | `STATUS` | read; writing 1 to bit 4 clears the error | 0 | Bit 0 `INT0`, bit 1 `INT1`, bit 2 `DREQ`, bit 3 `BUSY`, bit 4 `ERROR` |
| 7 | `IRQ_MASK` | read and write | 0 | Bit 0 enables `INT0`, bit 1 enables `INT1` on the `o_irq` output |
| 8 | `TIMING` | read and write | from the generics | Bits 7:0 setup, 15:8 pulse, 23:16 recovery, in clock cycles |

Unlisted bits read zero and writes to them are ignored. On the ports, only the 16 low bits of the data go to the chip.

## 3. Behavior

### 3.1. Chip access

Writing to a port requests a 16-bit write of the data to that port. Reading a port requests a read; the processor read itself returns zero and the chip data is in `RDATA` when `BUSY` falls. The program reads a port, waits for `BUSY` to be zero and reads `RDATA`.

A request made while `BUSY` is one is dropped and sets the `ERROR` bit, which stays set until the program writes a one to it. The access in progress is not affected.

### 3.2. Pin timing

Each access goes through four stages, and the output pins come from registers.

| Stage | Duration in cycles | Pins |
| :--- | :--- | :--- |
| Setup | `TIMING[7:0]` | `OTG_CS_N` at 0, stable address and data, strobes at 1 |
| Pulse | `TIMING[15:8]` | `OTG_RD_N` or `OTG_WR_N` at 0 |
| Hold | 1 | `OTG_CS_N` at 0, strobes at 1, data kept |
| Recovery | `TIMING[23:16]` | All inactive, before the next access |

A field with value zero lasts one cycle. The reset values of `TIMING` come from the generics. The data output is enabled only on writes, from setup to hold.

The read data goes through a two-stage synchronizer and is sampled in the last cycle of the pulse. For the chip data to arrive in time, the pulse must last the access time of the chip, in cycles, plus three clock cycles.

### 3.3. Interrupts and DMA

The chip interrupt inputs and the DMA request go through two-stage synchronizers. `STATUS` shows the level of each interrupt already normalized to active at one (the `int_active_high` generic gives the pin polarity). The `o_irq` output is level-type and is one while any `INTn` is active with the matching `IRQ_MASK` bit at one. The program clears the cause in the chip itself. A board with a single interrupt pin connects bit 0 and leaves bit 1 inactive.

### 3.4. How software reads the chip identifier

With the chip out of reset (`CTRL` bit 0 at zero and the chip start-up time elapsed), the program follows the protocol of the chip. The identifier register codes and the expected values are in the datasheet of each chip.

| Chip | Sequence |
| :--- | :--- |
| ISP1362, host controller | Write the host identifier register code to `HC_CMD`, request a read of `HC_DATA`, wait for `BUSY` to fall and read `RDATA` |
| ISP1362, device controller | The same with `DC_CMD` and `DC_DATA` |
| CY7C67200 through the HPI | Write the internal address to `DC_DATA` (port 2, `HPI_ADDRESS`), request a read of `HC_DATA` (port 0, `HPI_DATA`), wait and read `RDATA` |

C example, with the peripheral base defined by the platform:

```c
#include <stdint.h>

#define USB_BASE   0x40000000u
#define USB_REG(n) (*(volatile uint32_t *)(USB_BASE + 4u * (n)))

enum { HC_DATA, HC_CMD, DC_DATA, DC_CMD, RDATA, CTRL, STATUS, IRQ_MASK, TIMING };
#define STATUS_BUSY (1u << 3)

static void usb_wait(void) {
    while (USB_REG(STATUS) & STATUS_BUSY) { }
}

static uint16_t usb_read_reg(unsigned cmd_port, unsigned data_port, uint16_t code) {
    USB_REG(cmd_port) = code;
    usb_wait();
    (void)USB_REG(data_port);
    usb_wait();
    return (uint16_t)USB_REG(RDATA);
}

uint16_t usb_host_chip_id(uint16_t id_code) {
    USB_REG(CTRL) = 0;
    return usb_read_reg(HC_CMD, HC_DATA, id_code);
}
```

## 4. Interface

### 4.1. Generics

| Generic | Type | Default | Meaning |
| :--- | :--- | :--- | :--- |
| `setup_cycles` | `natural` from 0 to 255 | 2 | Reset value of the setup |
| `pulse_cycles` | `natural` from 0 to 255 | 6 | Reset value of the pulse |
| `recovery_cycles` | `natural` from 0 to 255 | 4 | Reset value of the recovery |
| `int_active_high` | `boolean` | `true` | The chip interrupts are active high |

### 4.2. Ports

| Port | Direction | Width | Meaning |
| :--- | :--- | ---: | :--- |
| `i_clk` | input | 1 | Module clock |
| `i_rst` | input | 1 | Synchronous reset, active at `'1'` |
| `i_data_in` | input | `word_t` | Write data |
| `i_address` | input | 4 | Word address |
| `i_write` | input | 1 | Write pulse |
| `i_read` | input | 1 | Read pulse |
| `o_data_out` | output | `word_t` | Read data, zero without `i_read` |
| `o_irq` | output | 1 | Level interrupt |
| `o_otg_cs_n` | output | 1 | `OTG_CS_N` |
| `o_otg_rd_n` | output | 1 | `OTG_RD_N` |
| `o_otg_wr_n` | output | 1 | `OTG_WR_N` |
| `o_otg_rst_n` | output | 1 | `OTG_RST_N` |
| `o_otg_addr` | output | 2 | `OTG_ADDR[1:0]` |
| `o_otg_data` | output | 16 | Data for `OTG_DATA[15:0]` |
| `o_otg_data_oe` | output | 1 | Enables the `OTG_DATA` output, for the tristate layer of the top |
| `i_otg_data` | input | 16 | Value of `OTG_DATA[15:0]` |
| `i_otg_int` | input | 2 | Chip interrupts (`OTG_INT`; the two lines on the ISP1362) |
| `i_otg_dreq` | input | 1 | `OTG_DC_DREQ` |
| `o_otg_dack` | output | 1 | `OTG_DC_DACK` |

## 5. Verification

The cocotb entity tests use a model of the access protocol (command followed by data, two controllers) and cover reset, register reads and writes on both controllers, timing measured on the pins, dropping while busy, interrupts in both polarities and random traffic. The formal proof is in `formal/usb_bridge_props.sv` (see [formal](../formal/formal.md)), with five mutants of the VHDL.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
