"""Reset stretcher: the reset outlasts the request by a fixed count."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.dut import Dut

CYCLES = 8
OBSERVED = CYCLES - 1
CLOCK_NS = 10


async def high_cycles(dut: Dut, limit: int) -> int:
    """Count the clock edges that o_rst stays high.

    Parameters
    ----------
    dut : Dut
        The design under test.
    limit : int
        Edges after which the count stops.

    Returns
    -------
    int
        Number of edges with o_rst high.
    """
    count = 0
    for _ in range(limit):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        count += int(dut.o_rst.value)
    return count


@cocotb.test()
async def test_power_up_and_request(dut: Dut) -> None:
    """The reset is high after power-up and after each request."""
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    dut.i_rst.value = 0
    check_true(await high_cycles(dut, 3 * CYCLES) in (OBSERVED, CYCLES))
    dut.i_rst.value = 1
    await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0
    check_equal(await high_cycles(dut, 3 * CYCLES), OBSERVED)
    check_equal(int(dut.o_rst.value), 0)


@cocotb.test()
async def test_held_request(dut: Dut) -> None:
    """A request held for several cycles extends the reset."""
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    dut.i_rst.value = 1
    for _ in range(5):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0
    await Timer(1, unit="ns")
    check_equal(int(dut.o_rst.value), 1)
    check_equal(await high_cycles(dut, 3 * CYCLES), OBSERVED)
