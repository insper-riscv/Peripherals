"""Behavioural DDR output of the pins."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut

CLOCK_NS = 8
PAIRS = ((0x01, 0x1E), (0x15, 0x0A), (0x1F, 0x00), (0x00, 0x1F))


@cocotb.test()
async def test_output_halves(dut: Dut) -> None:
    """The rising value shows in the high half."""
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    dut.i_d_rise.value = 0
    dut.i_d_fall.value = 0
    await RisingEdge(dut.i_clk)
    for rise, fall in PAIRS:
        dut.i_d_rise.value = rise
        dut.i_d_fall.value = fall
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        check_equal(int(dut.o_q.value), rise)
        await FallingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        check_equal(int(dut.o_q.value), fall)
