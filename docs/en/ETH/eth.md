# 10/100 Mbit/s Ethernet MAC over MII

🌐 [Português](../../pt-br/ETH/eth.md) · [English](../../en/ETH/eth.md)

## 1. What it is

A bus peripheral that connects an Ethernet PHY through the MII and hands whole frames to the program. It sends frames with preamble, SFD, padding and FCS, and it receives them while checking the FCS and filtering by destination address. Each instance serves one PHY and carries the MDIO master that configures that PHY, so the two Ethernet ports of the DE2-115 (Marvell 88E1111 PHYs, ENET0 and ENET1) are two independent instances of the same peripheral.

The DE2-115 manual states that the board supports RGMII (the factory default) and MII on both PHYs, selected by one jumper per PHY (JP1 and JP2). The peripheral implements the MII mode at 10 and 100 Mbit/s, and the jumper of the PHY must be in the MII position. The 1 Gbit/s RGMII mode is not part of the peripheral, because it needs DDR registers at the pins and an 8-bit data path at 125 MHz.

## 2. Structure

The `eth` entity is a structural top. The logic lives in single-purpose blocks, each in a single clock domain.

| Block | Domain | Function |
| :--- | :--- | :--- |
| `eth_regs` | system | Decodes the bus and holds control, filter, send length, MDIO command, counters and interrupts |
| `eth_mac_tx` | PHY `TX_CLK` | Generates preamble, SFD, buffer bytes, padding, FCS and the gap between frames |
| `eth_mac_rx` | PHY `RX_CLK` | Finds the SFD, assembles bytes, checks the FCS and delivers the bytes without the FCS plus a final word with the flags |
| `eth_async_fifo` | `RX_CLK` and system | 9-bit queue with Gray-coded pointers between the receiver and the system |
| `eth_rx_store` | system | Drains the queue, filters by destination, writes the frame to the receive buffer and raises the counting events |
| `eth_dpram` | two clocks | Dual-port memory of the two frame buffers and of the queue |
| `eth_crc32` | each side | CRC-32 register that absorbs one nibble per cycle (one instance for sending and one for receiving) |
| `eth_pulse_cdc` | two clocks | Carries a pulse from one domain to the other (start of send and end of send) |
| `eth_reset_stretch` | system | Stretches the reset so the slow PHY domains see it |
| `eth_mdio` | system | Clause 22 MDIO master |

The send buffer is an `eth_dpram` written at the system clock and read at `TX_CLK`; the receive buffer is an `eth_dpram` written and read at the system clock. The program writes the send buffer only while the transmitter is idle, and reads the receive buffer only after the frame is ready, so no address is read and written at the same time.

## 3. Interface

### 3.1. Generics

| Generic | Default | Meaning |
| :--- | :--- | :--- |
| `clk_freq_hz` | 50000000 | System clock frequency, used to derive MDC |
| `mdc_freq_hz` | 2500000 | MDC frequency; the DE2-115 manual uses 2.5 MHz |
| `tx_buffer_addr_bits` | 9 | The send buffer has $2^n$ words (2 KiB with 9) |
| `rx_buffer_addr_bits` | 9 | The receive buffer has $2^n$ words (2 KiB with 9) |
| `rx_fifo_addr_bits` | 4 | The receive queue has $2^n$ bytes (at least 2) |
| `sync_stages` | 2 | Stages of the synchronizers between domains |
| `reset_cycles` | 64 | System clock cycles that the reset of the PHY domains lasts |

The MDC half period is $\lceil f_{clk} / (2 f_{mdc}) \rceil$ system cycles.

### 3.2. Ports

| Port | Direction | Description |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | System clock and synchronous reset, active at `'1'` |
| `i_write`, `i_read` | input | Bus write and read pulses |
| `i_address` | input | Word address, 6 bits |
| `i_data_in`, `o_data_out` | input, output | Write and read data, `word_t`; the registers use the low 32 bits |
| `o_irq` | output | Level interrupt, active at `'1'` |
| `i_mii_rx_clk` | input | `ENETn_RX_CLK` |
| `i_mii_rxd`, `i_mii_rx_dv`, `i_mii_rx_er` | input | `ENETn_RX_DATA[3:0]`, `ENETn_RX_DV`, `ENETn_RX_ER` |
| `i_mii_tx_clk` | input | `ENETn_TX_CLK` |
| `o_mii_txd`, `o_mii_tx_en`, `o_mii_tx_er` | output | `ENETn_TX_DATA[3:0]`, `ENETn_TX_EN`, `ENETn_TX_ER` (always `'0'`) |
| `o_mdc` | output | `ENETn_MDC` |
| `i_mdio`, `o_mdio_out`, `o_mdio_oe` | input, output, output | The `ENETn_MDIO` pin split into input, output and output enable for the tristate layer of the platform top |
| `i_phy_int_n` | input | `ENETn_INT_N`, active at `'0'` |
| `o_phy_rst_n` | output | `ENETn_RST_N`, active at `'0'` |

The pins `ENETn_GTX_CLK`, `ENETn_RX_COL`, `ENETn_RX_CRS`, `ENETn_LINK100` and `ENETCLK_25` are not used by full-duplex MII and stay free on the platform.

## 4. Registers

The address is a word address with 6 bits, and the block takes 64 words (256 bytes). The byte offset is four times the word number. Addresses not listed read zero and ignore writes.

| Word | Name | Access | Reset | Description |
| ---: | :--- | :--- | :--- | :--- |
| 0 | `CTRL` | read and write | `0x04` | Control, bits in table 4.1 |
| 1 | `STATUS` | read | 0 | State, bits in table 4.2 |
| 2 | `IRQ_STATUS` | read; writing 1 clears | 0 | Pending interrupts, bits in table 4.3 |
| 3 | `IRQ_ENABLE` | read and write | 0 | Enables each interrupt of `IRQ_STATUS` |
| 4 | `MAC_LO` | read and write | 0 | First four octets of the MAC address; the first octet is in bits 7:0 |
| 5 | `MAC_HI` | read and write | 0 | Last two octets in bits 15:0; the fifth octet is in bits 7:0 |
| 6 | `TX_LEN` | read and write | 0 | Length in bytes of the frame to send, without FCS; ignored while sending |
| 7 | `TX_CMD` | write | | Bit 0 starts the send; bit 1 returns the send buffer pointer to zero |
| 8 | `TX_DATA` | read and write | 0 | A write appends a word to the send buffer (first byte in bits 7:0); a read returns the number of words written |
| 9 | `RX_LEN` | read | 0 | Length in bytes of the ready frame, without FCS; zero with no frame |
| 10 | `RX_DATA` | read | | Each read returns the next word of the ready frame (first byte in bits 7:0) |
| 11 | `RX_CMD` | write | | Bit 0 releases the frame and opens the buffer to a new one; bit 1 returns the read pointer to zero |
| 12 | `MDIO_CMD` | read and write | 0 | A write starts an MDIO transaction, fields in table 4.4 |
| 13 | `MDIO_DATA` | read and write | 0 | Data to write to the PHY; after a read, the data read |
| 16 | `CNT_TX` | read; write clears | 0 | Frames sent |
| 17 | `CNT_RX` | read; write clears | 0 | Frames received and delivered to the buffer |
| 18 | `CNT_CRC` | read; write clears | 0 | Frames with a wrong FCS |
| 19 | `CNT_PHY` | read; write clears | 0 | Frames with `RX_ER`, an odd number of nibbles or fewer than 64 bytes |
| 20 | `CNT_DROP` | read; write clears | 0 | Frames dropped because the buffer was busy, the frame was larger than the buffer, the queue lost bytes or the MAC was disabled |
| 21 | `CNT_FILTER` | read; write clears | 0 | Frames refused by the address filter |

### 4.1. `CTRL` bits

| Bit | Name | Meaning |
| ---: | :--- | :--- |
| 0 | `ENABLE` | Enables frame reception |
| 1 | `PROMISCUOUS` | Accepts any destination address |
| 2 | `BROADCAST` | Accepts the destination `FF:FF:FF:FF:FF:FF` (1 at reset) |
| 3 | `MULTICAST` | Accepts group destinations (bit 0 of the first octet set) |
| 4 | `ACCEPT_ERRORS` | Also delivers frames with FCS, PHY or size errors |
| 5 | `SOFT_RESET` | Writing 1 resets the MAC and all registers; always reads 0 |
| 6 | `PHY_RESET` | Holds `ENETn_RST_N` at `'0'` while it is 1 |

### 4.2. `STATUS` bits

| Bit | Name | Meaning |
| ---: | :--- | :--- |
| 0 | `TX_BUSY` | A send is in progress |
| 1 | `RX_READY` | A frame is ready in the receive buffer |
| 2 | `MDIO_BUSY` | An MDIO transaction is in progress |
| 3 | `PHY_INT` | `ENETn_INT_N` is at `'0'` |
| 4 | `MDIO_NOACK` | No PHY answered the last MDIO read |

### 4.3. `IRQ_STATUS` and `IRQ_ENABLE` bits

| Bit | Name | Source |
| ---: | :--- | :--- |
| 0 | `RX_FRAME` | Frame received and delivered to the buffer |
| 1 | `TX_DONE` | Frame sent |
| 2 | `ERROR` | Frame received with an FCS or PHY error or dropped, send start refused, or write to the send buffer refused |
| 3 | `MDIO_DONE` | MDIO transaction finished |
| 4 | `PHY` | Level of `ENETn_INT_N`; it follows the line and is not cleared by a write |

The `o_irq` output is `'1'` when some bit of `IRQ_STATUS` coincides with the matching bit of `IRQ_ENABLE`.

### 4.4. `MDIO_CMD` fields

| Bits | Name | Meaning |
| ---: | :--- | :--- |
| 4:0 | `REG` | Register address in the PHY |
| 9:5 | `PHY` | PHY address (16 for ENET0 and 17 for ENET1 of the DE2-115, per the manual) |
| 10 | `WRITE` | 1 writes `MDIO_DATA` to the register; 0 reads the register into `MDIO_DATA` |

A write to `MDIO_CMD` while `MDIO_BUSY` is 1 is ignored.

## 5. Operation

### 5.1. Sending

The program clears the pointer with `TX_CMD`, writes the words of the frame to `TX_DATA`, writes the length to `TX_LEN` and writes 1 to `TX_CMD`. The frame runs from the destination address to the last data byte, without FCS. The transmitter sends

1. seven `0x55` preamble bytes and the `0xD5` SFD;
2. the frame bytes, each byte as two nibbles, the low one first;
3. zeros until the frame reaches 60 bytes, when the length is smaller;
4. the FCS, which is the complement of the CRC-32 from the destination address to the end of the padding, sent with the least significant byte first;
5. a 96-bit gap with `TX_EN` at 0.

The CRC-32 uses the polynomial $x^{32}+x^{26}+x^{23}+x^{22}+x^{16}+x^{12}+x^{11}+x^{10}+x^8+x^7+x^5+x^4+x^2+x+1$ with initial value `0xFFFFFFFF`, and an intact frame with its FCS leaves the register at `0xDEBB20E3`. The send is refused, and the `ERROR` bit rises, when `TX_LEN` is zero or when a send is already in progress. The buffer pointer returns to zero at the end of each send.

### 5.2. Receiving

The receiver ignores the preamble up to the `0xD` nibble of the SFD and assembles the nibbles into bytes. The bytes go through a four-byte delay line, which holds back the FCS, and move on to the queue. At the end of the frame (`RX_DV` returns to 0) a final word carries the flags of the frame.

| Flag | Condition |
| :--- | :--- |
| `CRC` | The CRC-32 of the whole frame, FCS included, is not the residue |
| `PHY` | `RX_ER` was 1 during the frame |
| `ALIGN` | The frame has an odd number of nibbles |
| `RUNT` | The frame has fewer than 64 bytes with the FCS |
| `OVERFLOW` | The queue filled up and bytes were lost |
| `MISSED` | A frame was ignored before this one because the previous final word was still waiting for room in the queue |

The system side compares the first six bytes with the filter: it accepts the address of `MAC_LO` and `MAC_HI`, the broadcast address with `BROADCAST`, a group address with `MULTICAST` and any address with `PROMISCUOUS`. An accepted frame with no error flag (or with `ACCEPT_ERRORS`) that fits in the buffer becomes ready: `RX_READY` rises, `RX_LEN` shows the length and `RX_DATA` delivers the words. The buffer holds one frame at a time, and the next frame is dropped and counted in `CNT_DROP` until the program releases the frame with `RX_CMD`.

### 5.3. MDIO

The master sends a 32-bit preamble of ones, the start `01`, the operation code (`01` write, `10` read), the PHY and register addresses, the turnaround and 16 data bits, most significant bit first. It changes `MDIO` on the falling edge of `MDC` and samples the PHY on the rising edge. On a read the master releases the line in the first turnaround bit and the PHY answers `0` in the second; if that bit arrives as 1, `MDIO_NOACK` rises and the data read is `0xFFFF`. `MDC` stays at 0 outside transactions. With a 100 MHz clock and `mdc_freq_hz` of 2.5 MHz the half period divider is 20, which is the divider of 40 that the manual gives for a 2.5 MHz `MDC`.

### 5.4. Clock domains and reset

Four clocks coexist: the system clock, the PHY `RX_CLK` and `TX_CLK` (2.5 MHz at 10 Mbit/s and 25 MHz at 100 Mbit/s, each generated by the PHY) and `MDC`, which is a signal derived from the system clock. The crossings are

| Crossing | Mechanism |
| :--- | :--- |
| Receiver bytes to the system | Asynchronous FIFO with Gray-coded pointers and two-stage synchronizers |
| Start of send, system to `TX_CLK` | Pulse turned into a toggle, synchronized and turned back into a pulse |
| End of send, `TX_CLK` to the system | The same mechanism in the opposite direction |
| Send buffer words | Dual-port memory with independent clocks; the content stays still during the send |
| `ENETn_INT_N` | Two-stage synchronizer |

The system reset (`i_rst` or `SOFT_RESET`) is stretched by `reset_cycles` cycles and synchronized into each PHY domain. Both sides of the queue leave reset together.

### 5.5. Interrupts

`o_irq` is a level. The program reads `IRQ_STATUS`, handles each pending source and writes the handled bits back to it.

## 6. DE2-115 pins

The pin name of each PHY replaces `n` with 0 (ENET0) or 1 (ENET1). Jumper JP1 (ENET0) or JP2 (ENET1) is in MII (pins 2 and 3), and the PHY needs a hardware reset after the jumper is changed.

| Port | Board pin | I/O standard |
| :--- | :--- | :--- |
| `i_mii_rx_clk` | `ENETn_RX_CLK` | 2.5 V |
| `i_mii_rxd` | `ENETn_RX_DATA[3:0]` | 2.5 V |
| `i_mii_rx_dv` | `ENETn_RX_DV` | 2.5 V |
| `i_mii_rx_er` | `ENETn_RX_ER` | 2.5 V |
| `i_mii_tx_clk` | `ENETn_TX_CLK` | 2.5 V |
| `o_mii_txd` | `ENETn_TX_DATA[3:0]` | 2.5 V |
| `o_mii_tx_en` | `ENETn_TX_EN` | 2.5 V |
| `o_mii_tx_er` | `ENETn_TX_ER` | 2.5 V |
| `o_mdc` | `ENETn_MDC` | 2.5 V |
| `i_mdio`, `o_mdio_out`, `o_mdio_oe` | `ENETn_MDIO` | 2.5 V, through the tristate of the top |
| `i_phy_int_n` | `ENETn_INT_N` | 2.5 V |
| `o_phy_rst_n` | `ENETn_RST_N` | 2.5 V |

The `RX_CLK` and `TX_CLK` clocks enter the registers of the peripheral directly and need clock constraints in the platform `.sdc`, with the system, `RX_CLK` and `TX_CLK` clock groups declared asynchronous to each other.

## 7. C usage example

```c
#include <stdint.h>

#define ETH_BASE   0x80010000u  /* base address of the instance in the platform */
#define ETH(word)  (*(volatile uint32_t *)(ETH_BASE + 4u * (word)))

enum { CTRL = 0, STATUS = 1, IRQ_STATUS = 2, MAC_LO = 4, MAC_HI = 5,
       TX_LEN = 6, TX_CMD = 7, TX_DATA = 8, RX_LEN = 9, RX_DATA = 10,
       RX_CMD = 11, MDIO_CMD = 12, MDIO_DATA = 13 };

static void mdio_wait(void) { while (ETH(STATUS) & (1u << 2)) { } }

uint16_t phy_read(unsigned phy, unsigned reg) {
    ETH(MDIO_CMD) = (phy << 5) | reg;       /* read */
    mdio_wait();
    return (uint16_t)ETH(MDIO_DATA);
}

void eth_init(const uint8_t mac[6]) {
    ETH(MAC_LO) = mac[0] | mac[1] << 8 | mac[2] << 16 | (uint32_t)mac[3] << 24;
    ETH(MAC_HI) = mac[4] | mac[5] << 8;
    ETH(CTRL) = (1u << 0) | (1u << 2);      /* ENABLE and BROADCAST */
}

void eth_send(const uint8_t *frame, unsigned len) {
    while (ETH(STATUS) & 1u) { }            /* wait for the previous send */
    ETH(TX_CMD) = 2u;                       /* pointer to zero */
    for (unsigned i = 0; i < len; i += 4) {
        uint32_t word = 0;
        for (unsigned b = 0; b < 4 && i + b < len; b++)
            word |= (uint32_t)frame[i + b] << (8 * b);
        ETH(TX_DATA) = word;
    }
    ETH(TX_LEN) = len;
    ETH(TX_CMD) = 1u;                       /* start */
}

unsigned eth_receive(uint8_t *buf) {
    if (!(ETH(STATUS) & 2u)) return 0;      /* no frame ready */
    unsigned len = ETH(RX_LEN);
    for (unsigned i = 0; i < len; i += 4) {
        uint32_t word = ETH(RX_DATA);
        for (unsigned b = 0; b < 4 && i + b < len; b++)
            buf[i + b] = (uint8_t)(word >> (8 * b));
    }
    ETH(RX_CMD) = 1u;                       /* release the buffer */
    return len;
}
```

## 8. Verification

### 8.1. Entity tests

Each block has its own cocotb test, and the top is exercised against a PHY model on the MII and on the MDIO, with the CRC of the test frames computed by the Python standard library, independent of the VHDL.

| Test | What it covers |
| :--- | :--- |
| `EthTx` | Frames of 301 and 2048 bytes, padding, minimum gap between frames, 10 Mbit/s clock and a refused start |
| `EthRx` | Sizes from 60 to 1514 bytes, address filter, promiscuous mode, wrong FCS, PHY error, short frame, busy buffer and consecutive frames |
| `EthMdio` | Write, read of extreme patterns, absent PHY and the MDC period |
| `EthRegisters` | Reset values, read-back, interrupts, `INT_N`, `RESET_N` and software reset |
| `EthMacTx`, `EthMacRx`, `EthRegs`, `EthRxStore`, `EthMdioMaster` | Each block on its own |
| `EthCrc32` | Register state against the CRC-32 of the standard library and the FCS residue |
| `EthAsyncFifo` | Order and capacity with different clock ratios in both directions |
| `EthDpram`, `EthPulseCdc`, `EthResetStretch` | Memory, pulse crossing and stretched reset |

### 8.2. Formal proofs

The proofs use SymbiYosys on the netlist that GHDL synthesizes from the VHDL.

| Entity | File | Proof | Property |
| :--- | :--- | :--- | :--- |
| `eth_crc32` | `eth_crc32_props.sv` | induction | The state is the mirror of an independent CRC-32 model (non-reflected register, polynomial `0x04C11DB7`); `o_residue_ok` holds exactly at the residue; absorbing the complement of any state leads to the residue |
| `eth_async_fifo` | `eth_async_fifo_props.sv` | bounded, 30 steps, free clocks | Occupancy never exceeds the depth nor goes negative; without `o_full` there is still room and without `o_empty` there is still a word; the pointers are Gray codes of the binaries and change one bit per edge |
| `eth_regs` | `eth_regs_props.sv` | induction | Control, mask, pending flags, MAC address, length, pointer and transmitter state follow an ideal model; the interrupt is pending and enabled; the start pulse needs a free transmitter and a non-zero length |

Each proof has a cover and mutants that must make it fail. The proofs run through `formal/eth.sh`, called by `formal/run.sh`.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
