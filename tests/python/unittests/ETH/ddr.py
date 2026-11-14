"""Behavioural DDR input of the pins."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut

CLOCK_NS = 8
WIDTH_MASK = 0x1F
QUARTER_NS = CLOCK_NS // 4
SAMPLES = 24


async def drive_pin(dut: Dut, values: list[int]) -> None:
    """Change the pin a quarter period before every clock edge.

    Parameters
    ----------
    dut : Dut
        The design under test.
    values : list[int]
        One value per clock edge, rising and falling in turn.
    """
    await Timer(CLOCK_NS - QUARTER_NS, unit="ns")
    for value in values:
        dut.i_d.value = value
        await Timer(CLOCK_NS // 2, unit="ns")


@cocotb.test()
async def test_input_pairs(dut: Dut) -> None:
    """Each rising edge delivers the pair sampled before it."""
    dut.i_d.value = 0
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    values = [(index * 7 + 3) & WIDTH_MASK for index in range(SAMPLES)]
    cocotb.start_soon(drive_pin(dut, values))
    seen: list[tuple[int, int]] = []
    for _ in range(SAMPLES // 2 + 4):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        seen.append((int(dut.o_q_rise.value), int(dut.o_q_fall.value)))
    expected = [
        (values[2 * k], values[2 * k + 1]) for k in range(SAMPLES // 2 - 2)
    ]
    starts = [
        index
        for index in range(len(seen) - len(expected) + 1)
        if seen[index:][: len(expected)] == expected
    ]
    check_equal(len(starts), 1, f"pairs {seen}")


@cocotb.test()
async def test_input_changes_on_rising_edge(dut: Dut) -> None:
    """The outputs hold their value for a whole clock period."""
    dut.i_d.value = 0
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    cocotb.start_soon(drive_pin(dut, [1, 2, 3, 4, 5, 6, 7, 8]))
    await RisingEdge(dut.i_clk)
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    before = (int(dut.o_q_rise.value), int(dut.o_q_fall.value))
    await FallingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check_equal((int(dut.o_q_rise.value), int(dut.o_q_fall.value)), before)
