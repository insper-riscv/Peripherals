# Peripherals

🌐 [Português](README.md) · [English](README.en.md)

Memory-mapped peripherals of the RISC-V RV32 SoC: the blocks the core talks to over the bus, outside the core and the memories. The core, the memories, the top levels that wire them together, and the test programs live in other repositories of the [insper-riscv](https://github.com/insper-riscv) organization.

## 1. Documentation

- [AUTHORS.en.md](AUTHORS.en.md): authors with commits in the repository, with name and GitHub account.
- [CONTRIBUTING.en.md](CONTRIBUTING.en.md): mandatory contribution rules, VHDL-2008 standard, naming, headers, Python standards, and verification before opening a Pull Request.
- [CITATION.cff](CITATION.cff): software citation metadata.
- [docs/bugs/](docs/bugs/README.md): bugs found in the first simulation of the peripherals, with their fixes.
- [docs/en/formal/formal.md](docs/en/formal/formal.md): formal proofs of the peripherals, solver engines, and the aggregator rule that decides the `formal` CI check.
- [docs/en/PLIC/plic.md](docs/en/PLIC/plic.md): the PLIC (`riscv-plic-1.0.0` for one hart and one context: priorities, threshold, enable, claim and complete, level gateways and the `MEIP` output).
- [docs/en/CLINT/clint.md](docs/en/CLINT/clint.md): the CLINT (64-bit `mtime`, `mtimecmp` and `msip` in the SiFive layout, the `MTIP` and `MSIP` outputs, and the safe `mtimecmp` write).
- [docs/en/UART/serial_uart.md](docs/en/UART/serial_uart.md): the 8N1 serial UART, its queues, registers, errors, and timing parameters.
- [docs/en/UART/jtag_uart.md](docs/en/UART/jtag_uart.md): the UART over JTAG (the core registers, the host side and the limits), with the defect that shaped it in [docs/en/bugs/](docs/en/bugs/JTAG_UART_RESPOSTA_PERDIDA.md).
- [docs/en/flash-controller/flash_controller.md](docs/en/flash-controller/flash_controller.md): the FLASH controller (command, address, status and page buffer registers).
- [contracts/02-barramento-e-memoria.md](https://github.com/insper-riscv/Core/blob/main/docs/en/contracts/02-barramento-e-memoria.md): bus protocol adopted by the peripherals.

## 2. Repository Structure

| Path | Contents |
| :--- | :--- |
| `src/common/` | Common-Components submodule, edited only at its source |
| `src/GPIO/soc/` | General-purpose I/O: direction, output (load, set, clear, toggle), synchronized pin read, and per-pin rising-edge, falling-edge or level interrupts |
| `src/TIMER/soc/` | Timer and PWM: a counter with `TOP`, a prescaler, a duty-cycle comparator, an overflow status, and an interrupt |
| `src/CLINT/soc/` | CLINT: 64-bit `mtime` with a registered carry, `mtimecmp`, `msip` and the timer and software interrupt outputs |
| `src/UART/serial/` | Memory-mapped 8N1 UART: parameterized RX and TX queues, separate registers, levels, status and error flags, and an optional RX interrupt; the physical layer is the OpenCores `uart2bus`, vendored in the repository |
| `src/UART/jtag/` | UART over JTAG: the core writes and reads bytes through registers and a host does the same through the Virtual JTAG (`jtag_uart`); `cyclone-v/` holds the Virtual JTAG shell, board only |
| `src/PLIC/soc/` | PLIC: level gateways, priority arbiter with tie-break by id, registers in the `riscv-plic-1.0.0` layout and the `MEIP` output (`plic`) |
| `src/flash-controller/soc/` | FLASH controller: command, address, status and page buffer registers that carry the erase, program and protect commands to the FLASH chip of the Memory repository |
| `src/display/` | Seven-segment display: the value register, the hexadecimal-to-segments converter (`soc/`) and the board's Virtual JTAG shell (`cyclone-v/`) |
| `tests/python/` | Per-entity cocotb tests and the catalog (`tests.json`) that drives them, in `unittests/{CLINT,GPIO,PLIC,TIMER,UART,display,flash_controller}` |
| `tests/vhdl/` | `gpio_tb`, a wrapper that lets cocotb drive the `inout` pins of the GPIO |
| `formal/` | SystemVerilog properties of `gpio_cell`, `timer`, `clock_prescaler`, `counter_overflow`, `alu_ge_unsigned`, `clint`, `clint_mtime`, `plic`, `plic_gateway`, `plic_arbiter`, `flash_controller`, `uart_fifo`, and `uart`, the `run.sh`, and the engine aggregator |
| `docs/pt-br/`, `docs/en/` | CLINT documents (`CLINT/`), PLIC documents (`PLIC/`), UART documents (`UART/`), the FLASH controller (`flash-controller/`), formal proofs (`formal/`), and the defect of the UART over JTAG (`bugs/`) |

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

### 3.3. CLINT Registers

The address is 14 word bits. The layout is that of the SiFive CLINT, detailed in [docs/en/CLINT/clint.md](docs/en/CLINT/clint.md).

| Offset | Register |
| :--- | :--- |
| `0x0000` | `msip` (bit 0) |
| `0x4000`, `0x4004` | `mtimecmp` low and high (resets to all ones) |
| `0xBFF8`, `0xBFFC` | `mtime` low and high |

### 3.4. UART Registers

The UART does not require bus backpressure: software polls `TX_READY` and `RX_VALID`, and every memory-mapped access completes in one cycle. The initial configuration is 115200 baud, 8N1 at a 50 MHz clock, with 16-byte queues in each direction. Their depths are independent parameters.

| Address | Register |
| :--- | :--- |
| 0 | `TX_DATA` (write-only): queues the low byte; a read returns zero |
| 1 | `RX_DATA` (read-only): returns and removes the oldest received byte; a write has no effect |
| 2 | `STATUS`: bits 0 `RX_VALID`, 1 `TX_READY`, 2 `RX_OVERRUN`, 3 `TX_DROPPED`, 4 `RX_FULL`, 5 `TX_EMPTY`, 6 `TX_IDLE`, 15:8 `RX_LEVEL`, and 23:16 `TX_LEVEL`; writing 1 to bits 2 and 3 clears them |
| 3 | `CONTROL`: bit 0 enables the RX interrupt request |

## 4. Verification and Execution

### 4.1. Local execution

```bash
git clone --recurse-submodules https://github.com/insper-riscv/Peripherals.git
cd Peripherals
uv sync

make check   # VHDL syntax check of every source in dependency order (GHDL)
make test    # Per-entity cocotb tests (make test TEST=GPIO for one target)
make paths   # Paths of paths.yaml and the repository tree (riscv-tools check-tree)
make formal  # Formal proofs (SymbiYosys) with the engine of FORMAL_ENGINE (bitwuzla by default)
```

### 4.2. Execution via Docker

The `ghcr.io/insper-riscv/ci-vhdl:latest` image published by [insper-riscv/Infra](https://github.com/insper-riscv/Infra) includes GHDL (LLVM backend), Yosys, SymbiYosys, the Yices, Bitwuzla and Boolector solvers, `uv`, Python 3.14, and cocotb pre-installed:

```bash
docker run --rm -v "$PWD:/workspace" -w /workspace ghcr.io/insper-riscv/ci-vhdl:latest \
  bash -c "uv sync && make check && make test && make paths && make formal"
```

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](LICENSE).
