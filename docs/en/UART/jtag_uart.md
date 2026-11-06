# JTAG UART

## 1. What it is

A UART whose other end is a host on JTAG instead of a serial line: the core writes bytes that the host reads, and the host writes bytes that the core reads. It is the peripheral at id 4 (window `0xC0000000`) of the external bus of the core. The VHDL is `src/UART/jtag/jtag_uart.vhd`, and the Virtual JTAG shell of the board is `src/UART/jtag/cyclone-v/jtag_uart_shell.vhd`.

| Part | Role |
| :--- | :--- |
| Core side | Four word registers, one access per pulse of `we` or `re` (section 2) |
| Queues | Transmit and receive, 64 bytes each |
| Host side | The logic behind a Virtual JTAG instance (`sld_virtual_jtag` on the board, driven by the testbench in simulation), on the JTAG clock (section 3) |

The interconnect that decodes the address and gives the core the `ready` is in Insper-RISC-V (`src/interconnect/`, see its `ext_interconnect.md`).

## 2. The registers (core side)

| Word | Name | Read | Write |
| ---: | :--- | :--- | :--- |
| 0 | TXDATA | 0 | queue bits 7:0 for the host; dropped and flagged if the queue is full |
| 1 | RXDATA | bit 8 = a byte was waiting, bits 7:0 = that byte (removed); 0 when empty | ignored |
| 2 | STATUS | bits 7:0 free places in the transmit queue (0 to 64), bits 15:8 bytes in the receive queue, bit 16 a byte was dropped since the last read (the read clears it), bit 17 a host has scanned since the reset | ignored |
| 3 | CONTROL | Bit 0 `RX_IRQ_ENABLE`, bit 1 `TX_EMPTY_IRQ_ENABLE`, bit 2 `ERROR_IRQ_ENABLE`; zero after reset | Sets the three bits |

The `o_irq` output is a level and is the sum of three causes, each with its own enable.

| Cause | Condition | Stops holding when |
| :--- | :--- | :--- |
| Receive | A byte waits in the receive queue | The core reads the last byte of RXDATA |
| Transmit empty | The transmit queue is empty (the host took everything) | The core writes TXDATA |
| Error | A byte was dropped | The core reads STATUS, which clears bit 16 |

A write to a full queue never blocks the core. A program that must not stop when no host is attached reads bit 17 of STATUS: while it is 0 nobody listens and the program does not print; once it is 1 the program waits for a free place, up to a bound.

## 3. The host side

The UART is the second Virtual JTAG instance (instance index 1) next to the SDRAM debug port's. Its instruction register has 2 bits; instruction 1 selects a 48-bit data register.

| Direction | Bits | Meaning |
| :--- | :--- | :--- |
| in | 8 | push: give the byte below to the core |
| in | 7:0 | the byte (taken only if push is 1) |
| out | 31:0 | up to four bytes from the core, the first in bits 7:0 |
| out | 34:32 | how many of them are valid |
| out | 35 | the push of the command was dropped (receive queue full) |
| out | 36 | the previous scan was dropped: the command before it had not finished |
| out | 47:40 | bytes still waiting in the transmit queue |

Every accepted scan takes up to four bytes out of the transmit queue. The JTAG clock runs only during a scan, so an answer is shown by the second scan after its command (a scan shows the answer to the command of the scan before the previous one) and only once. A host that wants the output keeps scanning; one that wants to send a byte sets push in a scan.

## 4. Limits

| Item | Value |
| :--- | :--- |
| Bytes per scan, board to host | 4 |
| Bytes per scan, host to board | 1 |
| Queue depth | 64 bytes each way |
| Peripheral access | 1 core cycle plus the wait for `mem_advance` |

## 5. Verification and a fixed defect

The behavior is exercised through the bus, by the `ExtBus` system test of Insper-RISC-V (bytes in order, full queues, an answer shown once, the status flags). The block has an entity test of its own (queues, order, CONTROL and the three interrupt causes). The defect that shaped the host side is in [JTAG_UART_RESPOSTA_PERDIDA.md](../bugs/JTAG_UART_RESPOSTA_PERDIDA.md).
