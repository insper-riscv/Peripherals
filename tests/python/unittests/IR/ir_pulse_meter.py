"""Pulse meter of the infrared receiver: widths, filter, timeout."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.dut import Dut
from tests.python.utils import bus
from tests.python.utils.check import check

TIMEOUT = 200
TIMED_OUT = 2
EVENT_COUNT = 4
TOL = 4


async def start(dut: Dut) -> list[tuple[int, int]]:
    """Reset the meter and record its events and timeouts.

    Parameters
    ----------
    dut : Dut
        The design under test.

    Returns
    -------
    list[tuple[int, int]]
        Filled by the monitor with (kind, width); kind 1 is a mark,
        0 a space and 2 a timeout.
    """
    seen: list[tuple[int, int]] = []
    dut.i_line.value = 1
    await bus.hold_reset(dut)

    async def monitor() -> None:
        while True:
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            if int(dut.o_event.value) == 1:
                seen.append(
                    (int(dut.o_event_mark.value), int(dut.o_width.value))
                )
            if int(dut.o_timeout.value) == 1:
                seen.append((TIMED_OUT, 0))

    cocotb.start_soon(monitor())
    return seen


async def hold(dut: Dut, level: int, cycles: int) -> None:
    """Hold the line at a level for a number of cycles.

    Parameters
    ----------
    dut : Dut
        The design under test.
    level : int
        Line value.
    cycles : int
        Number of clock edges to hold it.
    """
    dut.i_line.value = level
    for _ in range(cycles):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


@cocotb.test()
async def test_widths(dut: Dut) -> None:
    """A mark and a space are reported with their width in cycles."""
    seen = await start(dut)
    await hold(dut, 1, 40)
    await hold(dut, 0, 100)
    await hold(dut, 1, 60)
    await hold(dut, 0, 10)
    await hold(dut, 1, 5)
    check(len(seen) == EVENT_COUNT, f"events {seen}")
    check(seen[0][0] == 0, "first event ends the idle space")
    check(seen[1][0] == 1 and abs(seen[1][1] - 100) <= TOL, f"mark {seen[1]}")
    check(seen[2][0] == 0 and abs(seen[2][1] - 60) <= TOL, f"space {seen[2]}")
    check(int(dut.o_active.value) == 0, "line high is idle")


@cocotb.test()
async def test_glitch_filter(dut: Dut) -> None:
    """A change shorter than the filter is not an event."""
    seen = await start(dut)
    await hold(dut, 1, 30)
    await hold(dut, 0, 1)
    await hold(dut, 1, 30)
    check(len(seen) == 0, f"glitch produced {seen}")
    await hold(dut, 0, 50)
    await hold(dut, 1, 1)
    await hold(dut, 0, 50)
    await hold(dut, 1, 10)
    marks = [event for event in seen if event[0] == 1]
    check(len(marks) == 1 and abs(marks[0][1] - 101) <= TOL, f"{seen}")


@cocotb.test()
async def test_timeout_once(dut: Dut) -> None:
    """A level that lasts too long raises one timeout."""
    seen = await start(dut)
    await hold(dut, 1, 5)
    await hold(dut, 0, 3 * TIMEOUT)
    timeouts = [event for event in seen if event[0] == TIMED_OUT]
    check(len(timeouts) == 1, f"timeouts {seen}")
    await hold(dut, 1, 10)
    check(
        len([event for event in seen if event[0] == TIMED_OUT]) == 1,
        "no second timeout",
    )
