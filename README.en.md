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
| `common/` | Blocks both use, one copy each (`GENERICS`, `GENERIC_FLIP_FLOP`, `GENERIC_MUX_4X1`, `GENERIC_MUX_8X1`, `TRISTATE_BUFFER_1BIT`) |
| `tests/python/` | Per-entity cocotb tests and the catalog (`tests.json`) that drives them, in `unittests/{common,GPIO,TIMER}` |
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

## 4. Verification and Running

```bash
git clone --recurse-submodules https://github.com/insper-riscv/Peripherals.git
git clone https://github.com/insper-riscv/Core.git   # next to it: FlipFlop
cd Peripherals
uv sync

make check   # VHDL syntax check of every source in dependency order (GHDL)
make test    # Per-entity cocotb tests (make test TEST=GPIO for one target)
make paths   # Existence of every path listed in the configuration
```

The tools (GHDL and uv) come from the `infra-toolchain` image of the [Infra](https://github.com/insper-riscv/Infra) repository, where continuous integration runs.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](LICENSE).
