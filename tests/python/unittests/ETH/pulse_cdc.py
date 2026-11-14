"""Pulse crossing: one pulse out for each pulse in."""

import cocotb
from cocotb.triggers import RisingEdge

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH.driver import hold, pulse, start_clocks

SOURCE_NS = 10
DESTINATION_NS = 37
PULSES = 12
SPACING = 12
RESET_EDGES = 4


async def count_outputs(dut: Dut, edges: int, widths: list[int]) -> int:
    """Count the pulses at the destination and record their widths.

    Parameters
    ----------
    dut : Dut
        The design under test.
    edges : int
        Destination clock edges to watch.
    widths : list[int]
        Receives the width in cycles of each pulse seen.

    Returns
    -------
    int
        Number of pulses seen.
    """
    pulses = 0
    run = 0
    for _ in range(edges):
        await RisingEdge(dut.i_dst_clk)
        if int(dut.o_pulse.value):
            run += 1
        elif run:
            pulses += 1
            widths.append(run)
            run = 0
    return pulses


@cocotb.test()
async def test_every_pulse_arrives(dut: Dut) -> None:
    """Twelve spaced pulses give twelve one-cycle pulses."""
    start_clocks((dut.i_src_clk, SOURCE_NS), (dut.i_dst_clk, DESTINATION_NS))
    dut.i_pulse.value = 0
    await hold(dut.i_dst_clk, [dut.i_src_rst, dut.i_dst_rst], RESET_EDGES)
    widths: list[int] = []
    watcher = cocotb.start_soon(
        count_outputs(dut, PULSES * SPACING * 2, widths)
    )
    for _ in range(PULSES):
        await RisingEdge(dut.i_src_clk)
        await pulse(dut.i_src_clk, dut.i_pulse)
        for _ in range(SPACING * DESTINATION_NS // SOURCE_NS):
            await RisingEdge(dut.i_src_clk)
    check_equal(await watcher, PULSES)
    check_equal(widths, [1] * PULSES)
