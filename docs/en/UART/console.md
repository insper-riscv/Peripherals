# Console

## 1. What it is

The console is the single text input and output interface of the SoC. The software and the interconnect see one peripheral, and a generic picks which of the two existing blocks serves it. The VHDL is `src/UART/console/console.vhd`.

| Backend | Block behind the interface | Other end | When to use |
| :--- | :--- | :--- | :--- |
| `jtag` (default) | [`jtag_uart`](jtag_uart.md) | Host on the JTAG chain, through a Virtual JTAG node | Every board with a JTAG chain that Quartus can reach, including the ones with no UART (DE0-CV, DE0-Nano, DE10-Lite) |
| `pinos` | [`uart`](serial_uart.md) | The `o_tx` and `i_rx` pins of the board | Boards with a UART or with a GPIO adapter |

The console has no logic of its own. It only chooses the instance from the `backend` generic and applies the polarity of the pins of the `pinos` backend. A `backend` value other than `jtag` or `pinos` stops the elaboration with an error.

## 2. Ports and generics

| Group | Ports | Backend |
| :--- | :--- | :--- |
| Peripheral bus | `i_clk`, `i_rst`, `i_addr` (8 bits), `i_wdata`, `i_we`, `i_re`, `o_rdata`, `o_irq` | Both |
| Pins | `i_rx` (default `'1'`), `o_tx` | `pinos`; in `jtag`, `o_tx` stays idle and `i_rx` is ignored |
| Flow | `i_cts` (default `'0'`, active), `o_rts` | `pinos` with `has_flow_control`; without it the input is ignored and `o_rts` stays active (low) |
| Virtual JTAG node | `i_tck`, `i_tdi`, `o_tdo`, `i_ir_in`, `i_state_cdr`, `i_state_sdr`, `i_state_udr`, `i_state_uir` | `jtag`; in `pinos`, `o_tdo` stays at zero and the inputs are ignored |

| Generic | Default | Effect |
| :--- | :--- | :--- |
| `backend` | `"jtag"` | Chooses the block |
| `baud_freq`, `baud_limit` | `16#240#`, `16#3AC9#` | Baud generator of the `uart` |
| `rx_fifo_depth`, `tx_fifo_depth` | 16 | Queues of the `uart` |
| `log2_depth` | 6 | Queues of the `jtag_uart`, 64 bytes each |
| `tx_invert`, `rx_invert` | `false` | Inverts the transmit or the receive pin of the `pinos` backend |
| `has_flow_control` | `false` | Adds the `i_cts` and `o_rts` lines to the UART of the `pinos` backend (see `serial_uart.md`); in `jtag`, `o_rts` stays active |

The inversion exists for the polarity resolved by the I/O role of the board (for example an RS-232 adapter with no level converter that inverts the signal). The peripheral itself always works with the line idle high.

## 3. Software contract

Both backends answer the same bus and share the shape of the words below. The rest of the map belongs to the backend and is in the document of the block.

| Word | Name | Common to both backends |
| ---: | :--- | :--- |
| 0 | TXDATA | Writing bits 7:0 queues a byte for transmission |
| 1 | RXDATA | Reading returns the oldest byte in bits 7:0 and removes it from the queue. Bit 8 is 1 to flag a valid byte in `jtag` |
| 2 | STATUS | Backend specific (section 2 of each block document) |
| 3 | CONTROL | Bits 0, 1 and 2 enable the receive, transmit-empty and error interrupts; zero after reset. In the `pinos` backend the other bits set the frame format and turn on the flow control (see `serial_uart.md`) |

The `o_irq` interrupt is level, the sum of the three enabled causes, in both backends. The platform wires `o_irq` to one of the two PLIC sources, which stay the same: id 1 for the serial UART (`UART`) and id 2 for the UART over JTAG (`UART_JTAG`).

## 4. Wiring in the top

The Virtual JTAG is a vendor primitive and is not part of the console. The structural top that uses the `jtag` backend instantiates the `sld_virtual_jtag` and connects its signals to the ports of the node (the `jtag_uart_shell` shell does it for the Cyclone V). The top that uses the `pinos` backend connects `i_rx` and `o_tx` to the pins already normalized by the `board.yaml`. The platform picks the backend through a generic of the top, and the software driver of the chosen backend lives in the `stdio` of the platform.

### 4.1. Console over RS-232

A board with an RS-232 port, such as the DE2-115 (DB9 connector behind the ZT3232 transceiver), uses the `pinos` backend with no adaptation in the peripheral. The transceiver of the board converts the 3.3 V levels to RS-232 levels and inverts the polarity, so the FPGA pin has the line idle high, as the peripheral expects, and `tx_invert` and `rx_invert` stay `false`. The default `baud_freq` and `baud_limit` generate 115200 baud with the 50 MHz clock (test `uart_default_baud.py`), and another clock needs new constants in the same ratio $\text{baud\_freq} / \text{baud\_limit} \approx 16 \, f_{baud} / f_{clk}$. The frame is 8N1 until the software writes `CONTROL`, and flow control (`CTS` and `RTS`) exists only with the `has_flow_control` generic, which connects the UART to the `i_cts` and `o_rts` ports of the console (active low, see `serial_uart.md`). Only an adapter with no level converter that inverts the signal needs `tx_invert` or `rx_invert` set to `true`.

## 5. Verification

| Proof | Where | What it shows |
| :--- | :--- | :--- |
| `ConsoleJtag` entity test | `tests/python/tests.json` | The console with `jtag` passes the same entity tests as the `jtag_uart` |
| `ConsolePins` and `ConsolePinsInverted` entity tests | `tests/python/unittests/UART/console_pins.py` | Reset, 8N1 transmit frame, receive frame, interrupt, with normal and inverted polarity |
| `console` formal | `formal/console_props.sv` and `tests/vhdl/console_equiv.vhd` | Miter: the console output equals that of the chosen block, with the polarity as an explicit inversion (bounded in cycles) |
| Mutants | `formal/run.sh` | Swapped polarity, address bits and strobe are caught by the proof |

The two blocks keep their own proofs (`uart`, `uart_fifo` and `jtag_uart`), which the console does not repeat.
