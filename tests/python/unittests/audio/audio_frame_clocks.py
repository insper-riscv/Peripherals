"""Clocks de bit e de canal: divisores e habilitação."""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import AudioFrameClocksDut

CYCLES = 200
PERIOD = 3


async def one_case(dut: AudioFrameClocksDut, div: int, slot: int) -> None:
    """Compare as saídas com o modelo de referência, ciclo a ciclo.

    Parameters
    ----------
    dut : AudioFrameClocksDut
        Clocks exercitados.
    div : int
        Inversões do mestre entre inversões do BCLK.
    slot : int
        Ciclos de BCLK por canal.
    """
    dut.i_enable.value = 1
    dut.i_xck_edge.value = 0
    dut.i_bclk_div.value = div
    dut.i_slot_bits.value = slot
    await bus.hold_reset(dut)
    edges = 0
    for cycle in range(CYCLES):
        pulse = 1 if cycle % PERIOD != PERIOD - 1 else 0
        dut.i_xck_edge.value = pulse
        await bus.cycles(dut, 1)
        edges += pulse
        flips = edges // div
        want_bclk = flips % 2
        want_lrck = (flips // 2 // slot) % 2
        check(int(dut.o_bclk.value) == want_bclk, f"BCLK {div} {slot}")
        check(int(dut.o_lrck.value) == want_lrck, f"LRCK {div} {slot}")


@cocotb.test()
async def dividers_1_1(dut: AudioFrameClocksDut) -> None:
    """Divida por 1 e por 1 como o modelo."""
    await one_case(dut, 1, 1)


@cocotb.test()
async def dividers_2_3(dut: AudioFrameClocksDut) -> None:
    """Divida por 2 e por 3 como o modelo."""
    await one_case(dut, 2, 3)


@cocotb.test()
async def dividers_4_4(dut: AudioFrameClocksDut) -> None:
    """Divida por 4 e por 4 como o modelo."""
    await one_case(dut, 4, 4)


@cocotb.test()
async def disabled_stays_low(dut: AudioFrameClocksDut) -> None:
    """Mantenha BCLK e LRCK em zero com a geração desabilitada."""
    await one_case(dut, 1, 1)
    dut.i_enable.value = 0
    await bus.cycles(dut, 3)
    check(int(dut.o_bclk.value) == 0, "BCLK parado")
    check(int(dut.o_lrck.value) == 0, "LRCK parado")
