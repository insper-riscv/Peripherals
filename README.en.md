# Peripherals

🌐 [Português](README.md) · [English](README.en.md)

Memory-mapped peripherals of the RISC-V RV32 SoC: the blocks the core talks to over the bus, outside the core and the memories. The core, the memories, the top levels that wire them together, and the test programs live in other repositories of the [insper-riscv](https://github.com/insper-riscv) organization.

## 1. Documentation

- [AUTHORS.en.md](AUTHORS.en.md): authors with commits in the repository, with name and GitHub account.
- [CONTRIBUTING.en.md](CONTRIBUTING.en.md): mandatory contribution rules, VHDL-2008 standard, naming, headers, Python standards, and verification before opening a Pull Request.
- [CITATION.cff](CITATION.cff): software citation metadata.
- [docs/bugs/](docs/bugs/README.md): bugs found in the first simulation of the peripherals, with their fixes.
- [contracts/02-barramento-e-memoria.md](https://github.com/insper-riscv/Core/blob/main/docs/en/contracts/02-barramento-e-memoria.md): bus protocol adopted by the peripherals.

## 2. Repository Structure

| Path | Contents |
| :--- | :--- |
| `GPIO/` | General-purpose I/O: direction, output (load, set, clear, toggle), synchronized pin read, and per-pin rising/falling edge interrupts |
| `TIMER/` | Timer and PWM: a counter with `TOP`, a prescaler, a duty-cycle comparator, an overflow status, and an interrupt |
| `UART/` | Memory-mapped 8N1 UART: separate RX and TX byte registers, status and error flags, and an optional RX interrupt; the physical layer is the OpenCores `uart2bus`, vendored in the repository |
| `tests/python/` | Per-entity cocotb tests and the catalog (`tests.json`) that drives them, in `unittests/{common,GPIO,TIMER,UART}` |
| `tests/vhdl/` | `gpio_tb`, a wrapper that lets cocotb drive the GPIO inout pins |

## 3. Interface

Every peripheral shares the same set of ports, following the bus of the Core contract: `clock`, `clear`, `data_in`, `address` (word offset inside the peripheral), `write`, `read`, `data_out`, and `irq`. The register maps are in the `*_OPERATION_DECODER` entities and in `tests/python/unittests/*/*_operation_decoder.py`.

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

The UART does not require bus backpressure: software polls `TX_READY` and `RX_VALID`, and every memory-mapped access still completes in one cycle. The initial hardware configuration is 115200 baud, 8N1 at a 50 MHz clock. There are no RX or TX FIFOs: RX has one pending-byte register and the physical transmitter accepts one byte at a time.

| Address | Register |
| :--- | :--- |
| 0 | `TX_DATA` (write-only): writing the low byte starts the transmission; a read returns zero |
| 1 | `RX_DATA` (read-only): returns the received byte and clears `RX_VALID`; a write has no effect |
| 2 | `STATUS`: bit 0 `RX_VALID`, bit 1 `TX_READY`, bit 2 `RX_OVERRUN`, bit 3 `TX_DROPPED`; writing 1 to bits 2 and 3 clears them |
| 3 | `CONTROL`: bit 0 enables the RX interrupt request |

## 4. Verification and Running

```bash
git clone --recurse-submodules https://github.com/insper-riscv/Peripherals.git
git clone https://github.com/insper-riscv/Common-Components.git   # next to it: flip_flop, multiplexers, adder, and the register with clear
cd Peripherals
uv sync

make check   # VHDL syntax check of every source in dependency order (GHDL)
make test    # Per-entity cocotb tests (make test TEST=GPIO for one target)
make paths   # Existence of every path listed in the configuration
```

The tools (GHDL and uv) come from the `infra-toolchain` image of the [Infra](https://github.com/insper-riscv/Infra) repository, where continuous integration runs.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](LICENSE).
