# Peripherals

The memory-mapped peripherals of the RV32 SoC. One job: the blocks the core
talks to over the bus, outside the core and the memories. The core, the
memories, the top levels that wire them and the test programs live in other
repositories of [insper-riscv](https://github.com/insper-riscv).

## Layout

| Path | What |
| :--- | :--- |
| `GPIO/` | general-purpose I/O: direction, output (load, set, clear, toggle), synchronized pin read, per-pin rising/falling edge interrupts |
| `TIMER/` | timer/PWM: a counter with `TOP`, a prescaler, a duty-cycle comparator, an overflow status and interrupt |
| `common/` | blocks both use, one copy each (`GENERICS`, `GENERIC_FLIP_FLOP`, `GENERIC_MUX_4X1`, `GENERIC_MUX_8X1`, `TRISTATE_BUFFER_1BIT`) |
| `tests/python/` | per-entity cocotb tests and the catalog (`tests.json`) that drives them; `unittests/{common,GPIO,TIMER}` |
| `tests/vhdl/` | `gpio_tb`, a wrapper that lets cocotb drive the GPIO's inout pins |

UART will join when the bus has `ready` and the interrupt path exists.

## The interface

Every peripheral shares one shape (the bus design of
[Core's `docs/contracts/02-barramento-e-memoria.md`](https://github.com/insper-riscv/Core/blob/main/docs/contracts/02-barramento-e-memoria.md)):
`clock`, `clear`, `data_in`, `address` (the word offset inside the peripheral),
`write`, `read`, `data_out`, `irq`. The register maps are in the
`*_OPERATION_DECODER` entities, and in `tests/python/unittests/*/*_operation_decoder.py`.

| GPIO address | Register |
| :--- | :--- |
| 0 | direction (1 = output) |
| 1, 2, 3, 4 | output: load, set, clear, toggle (a read returns the output register) |
| 5, 6, 7 | interrupt mask, rising-edge mask, falling-edge mask |
| 8 | interrupt status (a read returns it and clears it) |
| 9 | the pins, after a two-stage synchronizer |

| TIMER address | Register |
| :--- | :--- |
| 0 | config: bit 0 start, 1 saturate at `TOP` (else wrap), 2 PWM enable, 3 interrupt enable |
| 1 | counter (a write loads it) |
| 2 | counter reset (a write clears it) |
| 3, 4 | `TOP` (resets to all ones), duty cycle |
| 5 | overflow status (a read returns it and clears it) |
| 6 | PWM output |
| 7 | prescaler (the counter advances every `prescaler + 1` cycles) |

## Use

```bash
git clone --recurse-submodules https://github.com/insper-riscv/Peripherals.git
git clone https://github.com/insper-riscv/Core.git   # next to it: FlipFlop
cd Peripherals
uv sync
make check   # GHDL syntax check of every source, in dependency order
make test    # per-entity cocotb tests (TEST=GPIO for one)
make paths   # every path the configuration lists exists
```

The tools (GHDL, uv) come from the `infra-toolchain` image of
[Infra](https://github.com/insper-riscv/Infra); CI runs there.

## Where this came from

`GPIO/`, `TIMER/` and `common/` moved from `insper-riscv/RV32` (`src/GPIO`,
`src/TIMER`), with their history and authorship (`git filter-repo`). The five
blocks that both directories carried (three identical, two with the same ports and
different bodies, unified to the TIMER's version) are now one copy each in `common/`. The old
`src/GPIO/ROM_simulation.vhd` (a stale copy of the ROM model) was archived as the
tag `archive/gpio-rom-simulation` of RV32. The pre-move state is the tag
`pre-refactor`.

The peripherals were never part of a working SoC top; the first time their
sources were simulated, GHDL rejected port-map expressions the Quartus compiler
accepts, and the tests found three bugs, documented with their fixes in
[docs/bugs/](docs/bugs/README.md).

## License

Apache License 2.0, see [LICENSE](LICENSE).
