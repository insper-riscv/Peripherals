"""Registrador de saída HDMI: cor, DE, sincronismos e reset."""

import random
from typing import Protocol

import cocotb
from cocotb.clock import Clock
from cocotb.handle import LogicArrayObject, LogicObject
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from tests.python.utils.check import check

CLOCK_NS = 10
CYCLES = 300


class OutDut(Protocol):
    """Sinais do registrador de saída, das saídas para as entradas."""

    o_d: LogicArrayObject
    o_de: LogicObject
    o_hs: LogicObject
    o_vs: LogicObject
    i_vs: LogicObject
    i_hs: LogicObject
    i_visible: LogicObject
    i_lit: LogicObject
    i_color: LogicArrayObject
    i_rst: LogicObject
    i_clk: LogicObject
    v_sync_positive: LogicObject
    h_sync_positive: LogicObject


async def start(dut: OutDut) -> None:
    """Inicia o clock e aplica o reset.

    Parameters
    ----------
    dut : OutDut
        Registrador sob teste.
    """
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    dut.i_rst.value = 1
    dut.i_color.value = 0xABCDEF
    dut.i_lit.value = 1
    dut.i_visible.value = 1
    dut.i_hs.value = 1
    dut.i_vs.value = 1
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


def check_idle(dut: OutDut) -> None:
    """Confere as saídas de repouso.

    Parameters
    ----------
    dut : OutDut
        Registrador sob teste.
    """
    check(int(dut.o_d.value) == 0, "cor preta no reset")
    check(int(dut.o_de.value) == 0, "DE baixo no reset")
    check(
        int(dut.o_hs.value) == int(not int(dut.h_sync_positive.value)),
        "HS no repouso",
    )
    check(
        int(dut.o_vs.value) == int(not int(dut.v_sync_positive.value)),
        "VS no repouso",
    )


@cocotb.test()
async def test_reset_then_registered_pass_through(dut: OutDut) -> None:
    """O reset leva ao repouso e, depois, a saída registra a entrada."""
    await start(dut)
    check_idle(dut)
    dut.i_rst.value = 0
    rng = random.Random(1)  # noqa: S311
    for _ in range(CYCLES):
        color = rng.randrange(1 << 24)
        lit, vis, hs, vs = (rng.randrange(2) for _ in range(4))
        dut.i_color.value = color
        dut.i_lit.value = lit
        dut.i_visible.value = vis
        dut.i_hs.value = hs
        dut.i_vs.value = vs
        await RisingEdge(dut.i_clk)
        await FallingEdge(dut.i_clk)
        check(
            int(dut.o_d.value) == (color if lit else 0),
            "cor mascarada por i_lit",
        )
        check(int(dut.o_de.value) == vis, "DE é a área visível")
        check(int(dut.o_hs.value) == hs, "HS passa")
        check(int(dut.o_vs.value) == vs, "VS passa")
        await Timer(1, unit="ns")


@cocotb.test()
async def test_reset_in_the_middle(dut: OutDut) -> None:
    """Um reset no meio da varredura leva as saídas ao repouso."""
    await start(dut)
    dut.i_rst.value = 0
    for _ in range(5):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check(int(dut.o_de.value) == 1, "DE alto antes do reset")
    dut.i_rst.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check_idle(dut)
