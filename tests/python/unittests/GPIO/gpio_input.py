"""GPIO só de entrada (32 pinos): leitura e interrupção.

O bloco é o grupo do GPIO com todos os pinos fixos em entrada e sem
porta de saída. O teste confere que a escrita em DIR não tem efeito,
que PINS é a entrada sincronizada, que a interrupção sai pelas bordas
e pelo nível e que a leitura de IRQ_STAT limpa as pendências.
"""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import GpioInputDut

DIR, OUT_LOAD, OUT_SET, OUT_CLR, OUT_TGL = 0, 1, 2, 3, 4
IRQ_MASK, RISE_MASK, FALL_MASK, IRQ_STAT, PINS, LEVEL_MASK = 5, 6, 7, 8, 9, 10
WORD = 0xFFFF_FFFF
PATTERN = 0xA5A5_A5A5
SYNC_CYCLES = 4
PIN_A = 1 << 3
PIN_B = 1 << 17


async def setup(dut: GpioInputDut) -> None:
    """Segure os pinos em zero e reinicie o bloco.

    Parameters
    ----------
    dut : GpioInputDut
        Bloco exercitado pelo teste.
    """
    dut.i_pins.value = 0
    await bus.reset(dut)


@cocotb.test()
async def test_output_registers_are_inert(dut: GpioInputDut) -> None:
    """DIR lê zero depois de escrito e nada pede interrupção."""
    await setup(dut)
    for address in (DIR, OUT_LOAD, OUT_SET, OUT_CLR, OUT_TGL):
        await bus.write(dut, address, PATTERN)
    check(await bus.read(dut, DIR) == 0, "DIR lê zero")
    check(int(dut.o_irq.value) == 0, "sem interrupção")


@cocotb.test()
async def test_pins_are_read_synchronized(dut: GpioInputDut) -> None:
    """PINS segue os pinos depois do sincronizador de dois estágios."""
    await setup(dut)
    dut.i_pins.value = PATTERN
    await bus.cycles(dut, 1)
    check(await bus.read(dut, PINS) != PATTERN, "ainda não sincronizou")
    await bus.cycles(dut, SYNC_CYCLES)
    check(await bus.read(dut, PINS) == PATTERN, "pinos sincronizados")
    check(int(dut.o_irq.value) == 0, "máscara zero, sem interrupção")


@cocotb.test()
async def test_edges_raise_the_interrupt(dut: GpioInputDut) -> None:
    """Subida e descida pedem interrupção só nos pinos mascarados."""
    await setup(dut)
    await bus.write(dut, IRQ_MASK, PIN_A | PIN_B)
    await bus.write(dut, RISE_MASK, PIN_A)
    await bus.write(dut, FALL_MASK, PIN_B)
    dut.i_pins.value = PIN_A | PIN_B
    await bus.cycles(dut, SYNC_CYCLES)
    check(await bus.read(dut, IRQ_STAT) == PIN_A, "só a subida de A")
    check(int(dut.o_irq.value) == 0, "a leitura limpou")
    dut.i_pins.value = PIN_A
    await bus.cycles(dut, SYNC_CYCLES)
    check(await bus.read(dut, IRQ_STAT) == PIN_B, "só a descida de B")
    check(int(dut.o_irq.value) == 0, "a leitura limpou de novo")


@cocotb.test()
async def test_level_mode(dut: GpioInputDut) -> None:
    """No modo de nível a pendência religa enquanto o nível vale."""
    await setup(dut)
    await bus.write(dut, IRQ_MASK, PIN_A)
    await bus.write(dut, RISE_MASK, PIN_A)
    await bus.write(dut, LEVEL_MASK, PIN_A)
    dut.i_pins.value = PIN_A
    await bus.cycles(dut, SYNC_CYCLES)
    check(await bus.read(dut, IRQ_STAT) == PIN_A, "nível alto pendente")
    await bus.cycles(dut, 1)
    check(int(dut.o_irq.value) == 1, "religa com o nível")
    dut.i_pins.value = 0
    await bus.cycles(dut, SYNC_CYCLES)
    await bus.read(dut, IRQ_STAT)
    await bus.cycles(dut, 1)
    check(int(dut.o_irq.value) == 0, "sem nível, sem pendência")
