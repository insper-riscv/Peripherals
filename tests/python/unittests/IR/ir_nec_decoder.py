"""NEC decoder of the infrared receiver, driven by pulse measures."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.dut import Dut
from tests.python.unittests.IR import nec
from tests.python.utils import bus
from tests.python.utils.check import check

UNIT = 562
TWO_ERRORS = 2


class Seen:
    """Frames and errors the decoder reported.

    Attributes
    ----------
    frames : list[tuple[int, int, int, int]]
        Each frame as (address, command, repeat, extended).
    errors : int
        Number of error pulses.
    """

    def __init__(self) -> None:
        """Start with nothing seen."""
        self.frames: list[tuple[int, int, int, int]] = []
        self.errors = 0


async def start(dut: Dut) -> Seen:
    """Reset the decoder and start the monitor.

    Parameters
    ----------
    dut : Dut
        The design under test.

    Returns
    -------
    Seen
        What the monitor collects.
    """
    seen = Seen()
    dut.i_event.value = 0
    dut.i_event_mark.value = 0
    dut.i_width.value = 0
    dut.i_timeout.value = 0
    dut.i_ext_en.value = 1
    await bus.hold_reset(dut)

    async def monitor() -> None:
        while True:
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            if int(dut.o_frame_valid.value) == 1:
                seen.frames.append(
                    (
                        int(dut.o_address.value),
                        int(dut.o_command.value),
                        int(dut.o_repeat.value),
                        int(dut.o_extended.value),
                    )
                )
            seen.errors += int(dut.o_error.value)

    cocotb.start_soon(monitor())
    return seen


async def feed(dut: Dut, levels: list[nec.Level]) -> None:
    """Send each level as one measure event, then let the logic settle.

    Parameters
    ----------
    dut : Dut
        The design under test.
    levels : list[nec.Level]
        Levels as (mark, width in cycles); the first is a space event
        of the idle line, as the meter reports after a reset.
    """
    for mark, width in levels:
        dut.i_event.value = 1
        dut.i_event_mark.value = 1 if mark else 0
        dut.i_width.value = round(width)
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        dut.i_event.value = 0
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
    for _ in range(4):
        await RisingEdge(dut.i_clk)


@cocotb.test()
async def test_frames(dut: Dut) -> None:
    """Standard, extended and repeat frames are decoded."""
    seen = await start(dut)
    await feed(dut, [(False, 50000)])
    await feed(dut, nec.frame_levels(nec.frame_bytes(0x20, 0x3C, False)))
    await feed(dut, [(False, 40000)])
    await feed(dut, nec.repeat_levels())
    await feed(dut, [(False, 90000)])
    await feed(dut, nec.frame_levels(nec.frame_bytes(0xBEEF, 0x01, True)))
    check(
        seen.frames
        == [
            (0x20, 0x3C, 0, 0),
            (0x20, 0x3C, 1, 0),
            (0xBEEF, 0x01, 0, 1),
        ],
        f"frames {seen.frames}",
    )
    check(seen.errors == 0, "no errors")


@cocotb.test()
async def test_tolerance_edges(dut: Dut) -> None:
    """A bit space at the edge of the tolerance passes, beyond fails."""
    seen = await start(dut)
    data = nec.frame_bytes(0x20, 0x3C, False)
    levels = nec.frame_levels(data)
    # The first bit space is a zero of one unit; the limit is 25 %.
    levels[3] = (False, UNIT * 1.24)
    await feed(dut, levels)
    check(len(seen.frames) == 1 and seen.errors == 0, "inside")
    levels[3] = (False, UNIT * 1.4)
    await feed(dut, levels)
    check(len(seen.frames) == 1 and seen.errors == 1, "outside")


@cocotb.test()
async def test_timeout_and_recovery(dut: Dut) -> None:
    """A timeout inside a frame is an error and the decoder recovers."""
    seen = await start(dut)
    levels = nec.frame_levels(nec.frame_bytes(0x20, 0x3C, False))
    await feed(dut, levels[:20])
    dut.i_timeout.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_timeout.value = 0
    await feed(dut, [(False, 90000)])
    await feed(dut, levels)
    check(seen.errors == 1, f"errors {seen.errors}")
    check(seen.frames == [(0x20, 0x3C, 0, 0)], f"frames {seen.frames}")


@cocotb.test()
async def test_extended_off_and_bad_command(dut: Dut) -> None:
    """The extended address needs the enable; a bad complement fails."""
    seen = await start(dut)
    dut.i_ext_en.value = 0
    await feed(dut, nec.frame_levels(nec.frame_bytes(0x1234, 0x01, True)))
    check(seen.errors == 1 and not seen.frames, "extended refused")
    data = nec.frame_bytes(0x20, 0x3C, False)
    data[3] ^= 0x80
    await feed(dut, nec.frame_levels(data))
    check(seen.errors == TWO_ERRORS and not seen.frames, "bad command refused")
    data = nec.frame_bytes(0x20, 0x3C, False)
    await feed(dut, nec.frame_levels(data))
    check(len(seen.frames) == 1, "good frame still decodes")
