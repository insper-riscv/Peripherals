# Peripherals

🌐 [Português](README.md) · [English](README.en.md)

Memory-mapped peripherals of the RISC-V RV32 SoC: the blocks the core talks to over the bus, outside the core and the memories. The core, the memories, the top levels that wire them together, and the test programs live in other repositories of the [insper-riscv](https://github.com/insper-riscv) organization.

## 1. Documentation

- [AUTHORS.en.md](AUTHORS.en.md): authors with commits in the repository, with name and GitHub account.
- [CONTRIBUTING.en.md](CONTRIBUTING.en.md): mandatory contribution rules, VHDL-2008 standard, naming, headers, Python standards, and verification before opening a Pull Request.
- [CITATION.cff](CITATION.cff): software citation metadata.
- [docs/bugs/](docs/bugs/README.md): bugs found in the first simulation of the peripherals, with their fixes.
- [docs/en/UART/serial_uart.md](docs/en/UART/serial_uart.md): the 8N1 serial UART, its queues, registers, errors, and timing parameters.
- [docs/en/UART/jtag_uart.md](docs/en/UART/jtag_uart.md): the UART over JTAG (the core registers, the host side and the limits), with the defect that shaped it in [docs/en/bugs/](docs/en/bugs/JTAG_UART_RESPOSTA_PERDIDA.md).
- [contracts/02-barramento-e-memoria.md](https://github.com/insper-riscv/Core/blob/main/docs/en/contracts/02-barramento-e-memoria.md): bus protocol adopted by the peripherals.

## 2. Repository Structure

| Path | Contents |
| :--- | :--- |
| `src/common/` | Common-Components submodule, edited only at its source |
| `src/GPIO/soc/` | General-purpose I/O: direction, output (load, set, clear, toggle), synchronized pin read, and per-pin rising/falling edge interrupts |
| `src/TIMER/soc/` | Timer and PWM: a counter with `TOP`, a prescaler, a duty-cycle comparator, an overflow status, and an interrupt |
| `src/UART/serial/` | Memory-mapped 8N1 UART: parameterized RX and TX queues, separate registers, levels, status and error flags, and an optional RX interrupt; the physical layer is the OpenCores `uart2bus`, vendored in the repository |
| `src/UART/jtag/` | UART over JTAG: the core writes and reads bytes through registers and a host does the same through the Virtual JTAG (`jtag_uart`); `cyclone-v/` holds the Virtual JTAG shell, board only |
| `src/display/` | Seven-segment display: the value register, the hexadecimal-to-segments converter (`soc/`) and the board's Virtual JTAG shell (`cyclone-v/`) |
| `tests/python/` | Per-entity cocotb tests and the catalog (`tests.json`) that drives them, in `unittests/{GPIO,TIMER,UART,display}` |
| `tests/vhdl/` | `gpio_tb`, a wrapper that lets cocotb drive the `inout` pins of the GPIO |

## 3. Interface

Every peripheral shares the same set of ports, following the bus of the Core contract: `i_clk`, `i_rst`, `i_data_in`, `i_address` (word offset inside the peripheral), `i_write`, `i_read`, `o_data_out`, and `o_irq`. The register maps are in the `*_operation_decoder` entities and in `tests/python/unittests/*/*_operation_decoder.py`.

### 3.1. GPIO Registers

| Address | Register |
| :--- | :--- |
| 0 | Direction (1 = output) |
| 1, 2, 3, 4 | Output: load, set, clear, and toggle (a read returns the output register) |
| 5, 6, 7 | Interrupt mask, rising-edge mask, and falling-edge mask |
| 8 | Interrupt status (a read returns the value and clears it) |
| 9 | Pins, after a two-stage synchronizer |

### 3.2. TIMER Registers

| Address | Register |
| :--- | :--- |
| 0 | Configuration: bit 0 starts, bit 1 saturates at `TOP` (otherwise wraps), bit 2 enables PWM, bit 3 enables the interrupt |
| 1 | Counter (a write loads it) |
| 2 | Counter reset (a write clears it) |
| 3, 4 | `TOP` (resets to all ones) and duty cycle |
| 5 | Overflow status (a read returns the value and clears it) |
| 6 | PWM output |
| 7 | Prescaler (the counter advances every `prescaler + 1` cycles) |

### 3.3. UART Registers

The UART does not require bus backpressure: software polls `TX_READY` and `RX_VALID`, and every memory-mapped access completes in one cycle. The initial configuration is 115200 baud, 8N1 at a 50 MHz clock, with 16-byte queues in each direction. Their depths are independent parameters.

| Address | Register |
| :--- | :--- |
| 0 | `TX_DATA` (write-only): queues the low byte; a read returns zero |
| 1 | `RX_DATA` (read-only): returns and removes the oldest received byte; a write has no effect |
| 2 | `STATUS`: bits 0 `RX_VALID`, 1 `TX_READY`, 2 `RX_OVERRUN`, 3 `TX_DROPPED`, 4 `RX_FULL`, 5 `TX_EMPTY`, 6 `TX_IDLE`, 15:8 `RX_LEVEL`, and 23:16 `TX_LEVEL`; writing 1 to bits 2 and 3 clears them |
| 3 | `CONTROL`: bit 0 enables the RX interrupt request |

## 4. Verification and Running

```bash
git clone --recurse-submodules https://github.com/insper-riscv/Peripherals.git
cd Peripherals
uv sync

make check   # VHDL syntax check of every source in dependency order (GHDL)
make test    # Per-entity cocotb tests (make test TEST=GPIO for one target)
make paths   # Existence of every path listed in the configuration
```

The tools (GHDL and uv) come from the `ci-vhdl` image of the [Infra](https://github.com/insper-riscv/Infra) repository, where continuous integration runs.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](LICENSE).
