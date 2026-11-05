"""HEX_TO_SEG7: the seven-segment pattern of each hexadecimal digit."""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.display.patterns import PATTERNS
from tests.python.utils.check import check
from tests.python.utils.dut import Seg7Dut

ALL_OFF = 0b1111111
DIGITS = 16


async def _segments(dut: Seg7Dut, digit: int) -> int:
    """Apply a digit and return the segment pattern.

    Parameters
    ----------
    dut : Seg7Dut
        The design under test.
    digit : int
        The hexadecimal digit.

    Returns
    -------
    int
        The segments g..a.
    """
    dut.i_digit.value = digit
    await Timer(1, unit="ns")
    return int(dut.o_seg.value)


@cocotb.test()
async def test_every_digit_has_its_pattern(dut: Seg7Dut) -> None:
    """Each of the sixteen digits lights its own segments."""
    for digit, pattern in enumerate(PATTERNS):
        value = await _segments(dut, digit)
        check(value == pattern, f"digit {digit:X}: {value:07b}")


@cocotb.test()
async def test_patterns_are_distinct(dut: Seg7Dut) -> None:
    """No two digits show the same glyph."""
    seen = {await _segments(dut, digit) for digit in range(DIGITS)}
    check(len(seen) == DIGITS, f"{len(seen)} distinct patterns")


@cocotb.test()
async def test_no_digit_turns_every_segment_off(dut: Seg7Dut) -> None:
    """Every digit lights at least one segment (low level)."""
    for digit in range(DIGITS):
        value = await _segments(dut, digit)
        check(value != ALL_OFF, f"digit {digit:X} is blank")
