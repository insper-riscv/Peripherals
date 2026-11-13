"""NEC frame generator that drives the pin of the infrared receiver.

The clock of the tests is 1 MHz, so one cycle is one microsecond and
the widths below are in microseconds. The pin is active low, as the
demodulator module of the board.
"""

import random

from cocotb.triggers import Timer

from tests.python.utils.dut import IrDut

UNIT_US = 562.5
LEAD_MARK_US = 9000.0
LEAD_SPACE_US = 4500.0
REPEAT_SPACE_US = 2250.0

type Level = tuple[bool, float]


def frame_bytes(address: int, command: int, extended: bool) -> list[int]:
    """Return the four bytes of a NEC frame.

    Parameters
    ----------
    address : int
        Address, 8 bits or 16 bits when extended.
    command : int
        Command, 8 bits.
    extended : bool
        Whether the address takes the two bytes.

    Returns
    -------
    list[int]
        Address, address high or inverted, command, inverted command.
    """
    low = address & 0xFF
    high = (address >> 8) & 0xFF if extended else ~address & 0xFF
    return [low, high, command & 0xFF, ~command & 0xFF]


def frame_levels(
    data: list[int],
    rng: random.Random | None = None,
    jitter: float = 0.0,
    stop: bool = True,
) -> list[Level]:
    """Return the (mark, width) levels of a frame.

    Parameters
    ----------
    data : list[int]
        The four bytes, sent least significant bit first.
    rng : random.Random | None
        Source of the width jitter.
    jitter : float
        Maximum relative error of each width.
    stop : bool
        Whether the final mark is sent.

    Returns
    -------
    list[Level]
        Each level as (true for mark, width in microseconds).
    """

    def w(width: float) -> float:
        if rng is None or jitter == 0.0:
            return width
        return width * (1.0 + rng.uniform(-jitter, jitter))

    levels: list[Level] = [
        (True, w(LEAD_MARK_US)),
        (False, w(LEAD_SPACE_US)),
    ]
    for byte in data:
        for bit in range(8):
            levels.append((True, w(UNIT_US)))
            space = 3 * UNIT_US if (byte >> bit) & 1 else UNIT_US
            levels.append((False, w(space)))
    if stop:
        levels.append((True, w(UNIT_US)))
    return levels


def repeat_levels() -> list[Level]:
    """Return the levels of a NEC repeat code.

    Returns
    -------
    list[Level]
        Mark of 9 ms, space of 2.25 ms and the final mark.
    """
    return [
        (True, LEAD_MARK_US),
        (False, REPEAT_SPACE_US),
        (True, UNIT_US),
    ]


async def play(dut: IrDut, levels: list[Level], gap_us: float = 0.0) -> None:
    """Drive the pin through a sequence of levels and back to idle.

    Parameters
    ----------
    dut : IrDut
        The design under test.
    levels : list[Level]
        Levels to play.
    gap_us : float
        Idle time after the last level.
    """
    for mark, width in levels:
        dut.i_irda_rxd.value = 0 if mark else 1
        await Timer(round(width * 1000), unit="ns")
    dut.i_irda_rxd.value = 1
    if gap_us:
        await Timer(round(gap_us * 1000), unit="ns")
