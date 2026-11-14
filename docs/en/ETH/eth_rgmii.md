# 10, 100 and 1000 Mbit/s Ethernet MAC over RGMII

🌐 [Português](../../pt-br/ETH/eth_rgmii.md) · [English](../../en/ETH/eth_rgmii.md)

## 1. What it is

The same MAC as the `eth` peripheral (bus, registers, buffers, filter, counters and MDIO) wired to the PHY through RGMII, the factory mode of the two Marvell 88E1111 of the DE2-115 (jumper JP1 for ENET0 and JP2 for ENET1, on positions 1 and 2; the PHY needs a hardware reset after the jumper is changed). With RGMII the link runs at 10, 100 or 1000 Mbit/s, and the speed comes from the PHY over MDIO or is forced by the program.

The bus interface is that of `eth`. The differences are the PHY layer and one more register, `SPEED`.

## 2. Structure

| Entity | Function |
| :--- | :--- |
| `eth_rgmii_mac` | Structural top: instantiates `eth` with `gigabit` true and the `eth_rgmii` layer |
| `eth` | The MAC; with `gigabit` the data is 8 bits wide (GMII) and the `SPEED` register exists |
| `eth_rgmii` | Converts between the RGMII of the PHY and the GMII of the MAC and generates the transmit clock |
| `eth_ddr_in`, `eth_ddr_out` | DDR registers of the pins, thin leaves with two files of the same name (section 6) |
| `eth_speed` | `SPEED` register and periodic speed query to the PHY |
| `eth_mac_tx`, `eth_mac_rx`, `eth_crc32` | Send, receive and compute the CRC one nibble (MII) or one byte (GMII) per cycle |

The same `eth_mac_tx`, `eth_mac_rx` and `eth_crc32` serve MII and GMII. With the `i_wide` input at `'0'` they work one nibble per cycle; at `'1'` they work one byte per cycle.

## 3. Clock domains and speed

| Domain | Clock | Note |
| :--- | :--- | :--- |
| System | `i_clk` | Bus, receive buffer, MDIO and speed query |
| Transmit | `i_tx_clk` | Free-running 125 MHz from a PLL of the platform; the transmit MAC advances only with `o_tx_ce` |
| Receive | `i_rgmii_rxc` | RXC of the PHY: 125, 25 or 2.5 MHz according to the speed |

| Speed | Transmit | Receive |
| :--- | :--- | :--- |
| 1000 Mbit/s | One byte per 125 MHz cycle; 125 MHz TXC; low nibble on the rising edge and high on the falling edge | One byte per RXC cycle: low nibble on the rising edge and high on the falling edge |
| 100 Mbit/s | One nibble every 5 cycles (`o_tx_ce`); 25 MHz TXC at 50 % duty; the nibble goes out on both edges | One nibble per RXC cycle, the one of the rising edge; the falling one is ignored |
| 10 Mbit/s | One nibble every 50 cycles; 2.5 MHz TXC at 50 % | Same as 100 Mbit/s |

The 50 % duty of TXC at 25 and 2.5 MHz comes from the TXC DDR register: each 125 MHz cycle places one level in the high half and another in the low half, so five cycles form five high halves and five low halves. The receive error uses RX_CTL of the falling edge: $\mathrm{RX\_ER} = \mathrm{RX\_CTL}_{\downarrow} \oplus \mathrm{RX\_CTL}_{\uparrow}$, and the transmitter sends $\mathrm{TX\_CTL}_{\downarrow} = \mathrm{TX\_EN} \oplus \mathrm{TX\_ER}$, with `TX_ER` always `'0'`.

The MAC works in full duplex only. The duplex bit of the PHY appears in `SPEED`, but the MAC does not implement CSMA/CD.

### 3.1. Clock delay

RGMII requires the clock to reach the receiver about 2 ns shifted from the data, and the shift can be made by the transmitter, by the receiver or by the traces.

| Direction | What the design does | Confirmed in the manual |
| :--- | :--- | :--- |
| Transmit (MAC to PHY) | If `i_tx_clk_dly` is the 125 MHz clock shifted by 90 degrees (2 ns) by a PLL and `shifted_txc` is true, the MAC centres TXC on the data. If `i_tx_clk_dly` is `i_tx_clk` and `shifted_txc` is false, data and TXC leave aligned and the PHY must delay TXC | No. The manual does not say whether the 88E1111 delays TXC nor in which register the delay is enabled |
| Receive (PHY to MAC) | The design assumes RXC arrives centred on the data, that is, that the PHY inserts the delay, and the constraints of section 8 describe that assumption | No. The manual does not describe the internal delay of the 88E1111 and refers to the datasheet, which is not in the Docs folder |

If the PHY does not insert the receive delay, the adjustment is made in the constraints (input delay) or by a phase shift of RXC in the platform, without changing the entity. The position of the PHY register that enables each delay (register 20, bits 1 and 7 in the chip datasheet) comes from memory of the datasheet and is not confirmed in the board manual.

## 4. Interface

### 4.1. Generics of `eth_rgmii_mac`

| Generic | Default | Meaning |
| :--- | :--- | :--- |
| `clk_freq_hz`, `mdc_freq_hz` | 50 MHz, 2.5 MHz | As in `eth` |
| `tx_buffer_addr_bits`, `rx_buffer_addr_bits` | 9 | As in `eth` |
| `rx_fifo_addr_bits` | 11 | At 1000 Mbit/s the receive queue gets one byte per 125 MHz cycle and the system consumes one per `i_clk` cycle; with 11 bits (2048 bytes) a maximum frame fits even if the system does not consume during the frame. With a system clock of 125 MHz or more, 4 is enough |
| `sync_stages`, `reset_cycles` | 2, 64 | As in `eth` |
| `phy_addr` | 16 | MDIO address of the queried PHY; the manual gives 10000 (16) for ENET0 and 10001 (17) for ENET1 |
| `poll_cycles` | 50000 | System cycles between two speed queries (1 ms at 50 MHz) |
| `shifted_txc` | true | Describes `i_tx_clk_dly`, section 3.1 |

### 4.2. Ports of `eth_rgmii_mac`

| Port | Direction | DE2-115 pin (table 4-23 of the manual) |
| :--- | :--- | :--- |
| `i_clk`, `i_rst`, `i_write`, `i_read`, `i_address`, `i_data_in`, `o_data_out`, `o_irq` | | Bus of `eth` |
| `i_tx_clk` | input | 125 MHz clock of the platform |
| `i_tx_clk_dly` | input | Same clock shifted by 90 degrees, or `i_tx_clk` |
| `o_rgmii_txc` | output | `ENETn_GTX_CLK` (ENET0 A17, ENET1 C23) |
| `o_rgmii_txd[3:0]` | output | `ENETn_TX_DATA[3:0]` |
| `o_rgmii_tx_ctl` | output | `ENETn_TX_EN` |
| `i_rgmii_rxc` | input | `ENETn_RX_CLK` |
| `i_rgmii_rxd[3:0]` | input | `ENETn_RX_DATA[3:0]` |
| `i_rgmii_rx_ctl` | input | `ENETn_RX_DV` |
| `o_mdc`, `i_mdio`, `o_mdio_out`, `o_mdio_oe` | | `ENETn_MDC`, `ENETn_MDIO` (tristate in the platform top) |
| `i_phy_int_n`, `o_phy_rst_n` | | `ENETn_INT_N`, `ENETn_RST_N` |

All ENET pins are 2.5 V. The mapping of the RGMII signals to the names of table 4-23 (`TXC` on `GTX_CLK`, `TX_CTL` on `TX_EN`, `RX_CTL` on `RX_DV`) is the standard multiplexing of the 88E1111 and is not written in the text of the manual; figure 4-27 of the manual, which is not available as text, is the source to check. The pins `ENETn_TX_CLK`, `ENETn_TX_ER`, `ENETn_RX_ER`, `ENETn_RX_COL`, `ENETn_RX_CRS` and `ENETn_LINK100` stay free in RGMII. The direction and use of `ENETCLK_25` (A14, 3.3 V) are not in the manual.

Pins of ENET0 and ENET1 according to table 4-23:

| Signal | ENET0 | ENET1 |
| :--- | :--- | :--- |
| `GTX_CLK` (TXC) | A17 | C23 |
| `TX_DATA[0..3]` | C18, D19, A19, B19 | C25, A26, B26, C26 |
| `TX_EN` (TX_CTL) | A18 | B25 |
| `RX_CLK` | A15 | B15 |
| `RX_DATA[0..3]` | C16, D16, D17, C15 | B23, C21, A23, D21 |
| `RX_DV` (RX_CTL) | C17 | A22 |
| `MDC`, `MDIO` | C20, B21 | D23, D25 |
| `INT_N`, `RST_N` | A21, C19 | D24, D22 |

## 5. Registers

The registers of `eth` apply unchanged. `SPEED` takes word 14 (offset 0x38).

| Bits | Name | Access | Meaning |
| :--- | :--- | :--- | :--- |
| 1:0 | `MODE` | read and write | 0 automatic (reset), 1 forces 10, 2 forces 100, 3 forces 1000 Mbit/s |
| 5:4 | `ACTIVE` | read | Speed in use: 0 is 10, 1 is 100 and 2 is 1000 Mbit/s |
| 8 | `LINK` | read | The PHY reported link up in the last answered query |
| 9 | `FULL_DUPLEX` | read | The PHY reported full duplex |
| 10 | `RESOLVED` | read | The PHY reported speed and duplex resolved |

In automatic mode, `eth_speed` reads register 17 of the PHY every `poll_cycles` cycles and adopts bits 15 and 14 (00 is 10, 01 is 100 and 10 is 1000 Mbit/s) when bit 10 (link) and bit 11 (resolved) are 1 and the PHY answered. Without link the previous speed is kept; the reset value is 1000 Mbit/s. The fields of register 17 come from the 88E1111 datasheet and are not confirmed in the board manual.

The query uses the MDIO master of the MAC. While it lasts (about 26 µs at 2.5 MHz MDC), `STATUS.MDIO_BUSY` is 1 and a command written to `MDIO_CMD` is ignored, as with a master busy with a command of the program. Whoever uses MDIO checks the `MDIO_DONE` interrupt and repeats the command if it does not rise. The query does not raise `MDIO_DONE` and does not change `MDIO_NOACK`.

The speed should change only with the MAC idle. `ACTIVE` reaches the transmit and receive domains through synchronizers.

### 5.1. Example in C

```c
#define SPEED 14u
#define SPEED_MODE_1000 3u

uint32_t speed_in_use(void) {
    return (ETH(SPEED) >> 4) & 3u;      /* 0, 1 or 2 */
}

void speed_force_1000(void) { ETH(SPEED) = SPEED_MODE_1000; }
void speed_auto(void)       { ETH(SPEED) = 0; }
```

Sending and receiving frames follow section 7 of `eth.md`.

## 6. DDR primitives

| Entity | Simulation file | Board file |
| :--- | :--- | :--- |
| `eth_ddr_in` | `src/ETH/rgmii/sim/eth_ddr_in.vhd` | `src/ETH/rgmii/altera/eth_ddr_in.vhd` |
| `eth_ddr_out` | `src/ETH/rgmii/sim/eth_ddr_out.vhd` | `src/ETH/rgmii/altera/eth_ddr_out.vhd` |

The two files of each entity have the same name and ports, and a platform uses one of them. The board ones instantiate `altddio_in` and `altddio_out` by `component`, because Quartus 25.1 refuses direct instantiation of them (error 10481 with `entity altera_mf.altddio_in`); the GHDL of the tool image does not analyse them. The simulation ones are behavioural models.

| Entity | Behaviour |
| :--- | :--- |
| `eth_ddr_in` | `o_q_rise` is the data of the rising edge and `o_q_fall` that of the following falling edge, both registered on the rising edge of the next cycle |
| `eth_ddr_out` | Registers `i_d_rise` and `i_d_fall` on the rising edge and places the first on the pin in the high half and the second in the low half |

The `altddio_in` delivers the rising-edge data one cycle before the falling-edge data; the board wrapper registers the first once so the pair leaves aligned. The wrappers and the models were compared, over 190 cycles of random data with zero mismatches, against the simulation models of the Intel megafunction itself (`altera_mf.vhd`).

## 7. Verification

### 7.1. cocotb tests

The CRC of the test frames comes from `zlib.crc32`, independent of the VHDL, and the RGMII PHY is a Python model that generates RXC with the data 2 ns before each edge, samples TXD and TX_CTL on both edges of TXC and decodes the frames.

| Test | What it covers |
| :--- | :--- |
| `EthCrc32` | One byte per cycle and a mix of byte and nibble against the CRC-32 of the standard library |
| `EthGmiiTx` | Frames of 61 to 1514 bytes, padding, gap of 12 bytes, enable every 5 and every 50 cycles |
| `EthGmiiRx` | Frames of 60 to 1514 bytes, bad FCS, `RX_ER`, short frame |
| `EthDdrIn`, `EthDdrOut` | The models of the DDR registers |
| `EthRgmii`, `EthRgmiiInPhase` | The layer: bytes and nibbles on the pins, period and duty of TXC, shifted and in-phase TXC, input with a different nibble on the other edge |
| `EthRgmiiMac`, `EthRgmiiMacInPhase` | The top at 1000, 100 and 10 Mbit/s in both directions, errors, automatic speed through register 17 of an MDIO PHY, an MDIO read among the queries and a simulated ping (ICMP request received through the registers, reply sent and checked with checksums and FCS) |

The simulated ping does not replace the test on a real network on a board.

### 7.2. Formal proofs

| Entity | File | Proof | Property |
| :--- | :--- | :--- | :--- |
| `eth_crc32` | `eth_crc32_props.sv` | induction | With `i_wide` the state mirrors the non-reflected model after the byte (low nibble then high) |
| `eth_speed` | `eth_speed_props.sv` | induction and bounded | The mode is the data written; the speed in use is the learned or the forced one and never 11; the query reads register 17 of the configured PHY, never in the cycle of a request of the program, and the learned speed changes only with an answer, link and resolved |
| `eth_async_fifo` | `eth_async_fifo_props.sv` | bounded | `o_full_next` guarantees that the write of the next cycle fits, which allows writing one byte per cycle |

Each proof has a cover and mutants that must make it fail. The proofs run through `formal/eth.sh`.

## 8. Synthesis and constraints

### 8.1. Synthesis result

The minimal top (`eth_rgmii_mac` with the bus registers on virtual pins and the 125 MHz clocks on pins) was synthesised and fitted in Quartus Prime Lite 25.1 for the EP4CE115F29C7.

| Resource | Use |
| :--- | :--- |
| Logic elements | about 1850 of 114480 (2 %) |
| Registers | about 965 |
| M9K blocks | 7 |

| Clock | Fmax (slow model, 85 C) |
| :--- | :--- |
| 125 MHz transmit | about 147 MHz |
| `i_rgmii_rxc` | about 147 to 152 MHz |
| System (`i_clk`) | about 84 to 94 MHz; the longest path goes from the M9K output of the receive queue to the write address of `eth_rx_store` |

With the constraints of section 8.2, all setup slacks are positive (the smallest, 0.25 to 0.37 ns, at the TXC register of the shifted clock), and hold is positive in the slow models. In the fast model the hold of the RXC inputs was 0.11 ns negative with a minimum input delay of zero, a conservative value this constraint plan uses in place of the real delay of the PHY. The `M10K` attribute of `eth_dpram` raises a warning on the Cyclone IV E, which uses M9K.

### 8.2. Constraint plan (`.sdc`)

```tcl
create_clock -name clk50     -period 20.000 [get_ports CLOCK_50]
create_clock -name clk125    -period 8.000  [get_ports <i_tx_clk>]
create_clock -name clk125_90 -period 8.000 -waveform {2.000 6.000} [get_ports <i_tx_clk_dly>]
create_clock -name enet0_rxc -period 8.000  [get_ports ENET0_RX_CLK]
create_clock -name enet0_rxc_virt -period 8.000
derive_clock_uncertainty
set_clock_groups -asynchronous -group {clk50} \
    -group {clk125 clk125_90 enet0_txc} -group {enet0_rxc enet0_rxc_virt}
create_generated_clock -name enet0_txc -source [get_ports <i_tx_clk_dly>] \
    -master_clock clk125_90 [get_ports ENET0_GTX_CLK]
set_output_delay -clock enet0_txc -max  1.0 [get_ports {ENET0_TX_DATA[*] ENET0_TX_EN}]
set_output_delay -clock enet0_txc -min -1.0 [get_ports {ENET0_TX_DATA[*] ENET0_TX_EN}]
set_output_delay -clock enet0_txc -clock_fall -max  1.0 -add_delay [get_ports {ENET0_TX_DATA[*] ENET0_TX_EN}]
set_output_delay -clock enet0_txc -clock_fall -min -1.0 -add_delay [get_ports {ENET0_TX_DATA[*] ENET0_TX_EN}]
set_input_delay -clock enet0_rxc_virt -max 2.0 [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV}]
set_input_delay -clock enet0_rxc_virt -min 0.0 [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV}]
set_input_delay -clock enet0_rxc_virt -clock_fall -max 2.0 -add_delay [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV}]
set_input_delay -clock enet0_rxc_virt -clock_fall -min 0.0 -add_delay [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV}]
```

The 125 MHz clocks come from a PLL of the platform fed by `CLOCK_50` (PIN_Y2, 3.3 V); in the PLL, `clk125_90` is the second output with a 2000 ps phase. The RXC clock is declared at 125 MHz, the worst case; at 25 and 2.5 MHz the slacks only grow. The delay values (1.0 ns setup and hold at the output, 0 to 2.0 ns at the input) are conservative placeholders in the RGMII format and must be replaced by those of the RGMII standard and of the 88E1111 datasheet, which are not in the board manual. MDC and MDIO stay out of the analysis (false paths), because MDC is 2.5 MHz.

## 9. Limits

| Limit | Value |
| :--- | :--- |
| Duplex | Full duplex only |
| Buffers | One receive frame at a time and one transmit frame at a time, as in `eth` |
| Receive throughput at 1000 Mbit/s | Depends on `rx_fifo_addr_bits`, section 4.1; `eth_rx_store` consumes one byte per system cycle |
| 88E1111 items outside the manual | Bit positions of registers 17 and 20, internal delay and RGMII timing |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
