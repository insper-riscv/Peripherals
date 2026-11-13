"""Filtro de glitch PS/2: pulsos curtos descartados e níveis aceitos."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import Ps2FilterDut

FILTER_CYCLES = 4
SHORT_PULSE = FILTER_CYCLES - 1


async def setup(dut: Ps2FilterDut) -> None:
    """Inicie o clock e reinicie o filtro com a linha em repouso.

    Parameters
    ----------
    dut : Ps2FilterDut
        Filtro exercitado pelo teste.
    """
    dut.i_d.value = 1
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst_n.value = 1
    await bus.cycles(dut, 2)


@cocotb.test()
async def rests_high_after_reset(dut: Ps2FilterDut) -> None:
    """Mantenha a saída em 1 depois do reset."""
    await setup(dut)
    check(int(dut.o_d.value) == 1, "repouso em nível alto")


@cocotb.test()
async def discards_a_short_pulse(dut: Ps2FilterDut) -> None:
    """Descarte um pulso mais curto que o filtro."""
    await setup(dut)
    dut.i_d.value = 0
    for _ in range(SHORT_PULSE):
        await bus.cycles(dut, 1)
        check(int(dut.o_d.value) == 1, "saída não muda no pulso curto")
    dut.i_d.value = 1
    await bus.cycles(dut, FILTER_CYCLES + 2)
    check(int(dut.o_d.value) == 1, "saída segue em nível alto")


@cocotb.test()
async def accepts_a_long_level(dut: Ps2FilterDut) -> None:
    """Aceite um nível que dura o tempo do filtro."""
    await setup(dut)
    dut.i_d.value = 0
    await bus.cycles(dut, FILTER_CYCLES + 1)
    check(int(dut.o_d.value) == 0, "nível baixo aceito")
    dut.i_d.value = 1
    await bus.cycles(dut, FILTER_CYCLES + 1)
    check(int(dut.o_d.value) == 1, "nível alto aceito")
