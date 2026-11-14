"""Gerador de tom: semiciclo em quadros e habilitação."""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import AudioToneDut

HALF = 3
FRAMES = 20


@cocotb.test()
async def flips_every_half(dut: AudioToneDut) -> None:
    """Inverta a cada HALF pulsos e volte a zero sem habilitar."""
    dut.i_enable.value = 1
    dut.i_half.value = HALF
    dut.i_advance.value = 0
    await bus.hold_reset(dut)
    check(int(dut.o_level.value) == 0, "começa positivo")
    for frame in range(1, FRAMES + 1):
        dut.i_advance.value = 1
        await bus.cycles(dut, 1)
        dut.i_advance.value = 0
        await bus.cycles(dut, 1)
        want = (frame // HALF) % 2
        check(int(dut.o_level.value) == want, f"quadro {frame}")
    dut.i_enable.value = 0
    await bus.cycles(dut, 2)
    check(int(dut.o_level.value) == 0, "zera desabilitado")


@cocotb.test()
async def zero_half_flips_every_frame(dut: AudioToneDut) -> None:
    """Trate meio período zero como um quadro."""
    dut.i_enable.value = 1
    dut.i_half.value = 0
    dut.i_advance.value = 0
    await bus.hold_reset(dut)
    for frame in range(1, 6):
        dut.i_advance.value = 1
        await bus.cycles(dut, 1)
        dut.i_advance.value = 0
        await bus.cycles(dut, 1)
        check(int(dut.o_level.value) == frame % 2, f"quadro {frame}")
