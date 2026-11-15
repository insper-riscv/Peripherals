"""GPIO só de entrada com pinos ativos em nível baixo (32 pinos).

Os pinos 0 e 2 são ativos em nível baixo: o programa lê o nível
invertido, e a interrupção por subida vale para o nível ativo.
"""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import GpioInputDut

IRQ_MASK, RISE_MASK, IRQ_STAT, PINS = 5, 6, 8, 9
ACTIVE_LOW = 0b101
ALL_PINS = 0xFFFF_FFFF
SYNC_CYCLES = 4
PIN_0 = 1


@cocotb.test()
async def test_inverted_read(dut: GpioInputDut) -> None:
    """Com os pinos em zero, os ativos em nível baixo leem um."""
    dut.i_pins.value = 0
    await bus.reset(dut)
    await bus.cycles(dut, SYNC_CYCLES)
    check(await bus.read(dut, PINS) == ACTIVE_LOW, "leitura invertida")
    dut.i_pins.value = ALL_PINS
    await bus.cycles(dut, SYNC_CYCLES)
    check(
        await bus.read(dut, PINS) == ALL_PINS ^ ACTIVE_LOW,
        "pinos altos leem invertidos nos ativos em nível baixo",
    )


@cocotb.test()
async def test_interrupt_on_the_active_level(dut: GpioInputDut) -> None:
    """A subida lógica do pino 0 é a descida do nível elétrico."""
    dut.i_pins.value = ALL_PINS
    await bus.reset(dut)
    await bus.cycles(dut, SYNC_CYCLES)
    await bus.write(dut, IRQ_MASK, PIN_0)
    await bus.write(dut, RISE_MASK, PIN_0)
    dut.i_pins.value = ALL_PINS & ~PIN_0
    await bus.cycles(dut, SYNC_CYCLES)
    check(await bus.read(dut, IRQ_STAT) == PIN_0, "pendência no pino 0")
