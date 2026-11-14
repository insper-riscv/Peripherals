"""Shared checks of the decimal point of seg_display (has_dp true).

The bit of the point of digit k of a group is bit k of word 1 of the
group. o_hex has 8 bits per digit and the point is bit 7 of each digit;
a digit in no group never lights its point.
"""

from dataclasses import dataclass

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.display.patterns import PATTERNS
from tests.python.unittests.display.seg_display import (
    core_read,
    core_write,
    start,
)
from tests.python.unittests.dut import Dut
from tests.python.utils import jtag

GROUP_WORDS = 16
DP_WORD = 1
DIGIT_BITS = 8


@dataclass(frozen=True)
class DpLayout:
    """Layout and polarity of one display with decimal points.

    Attributes
    ----------
    digits : int
        Digits of the display.
    groups : tuple[tuple[int, ...], ...]
        Digit indices of each group, in the written order.
    active_low : bool
        Segments are lit at the low level.
    """

    digits: int
    groups: tuple[tuple[int, ...], ...]
    active_low: bool

    def listed(self) -> set[int]:
        """Return the digits that are in some group."""
        return {d for group in self.groups for d in group}


def expected_hex(layout: DpLayout, value: int, dots: int) -> int:
    """Return o_hex for a stored value and a mask of lit points."""
    out = 0
    for n in range(layout.digits):
        if n in layout.listed():
            seg = PATTERNS[(value >> (4 * n)) & 0xF]
            dot = (dots >> n) & 1
            # PATTERNS are low-level lit; the point is lit when dot is 1
            pins = seg | ((0 if dot else 1) << 7)
        else:
            pins = 0xFF
        if not layout.active_low:
            pins ^= 0xFF
        out |= pins << (DIGIT_BITS * n)
    return out


async def check_dp_groups(dut: Dut, layout: DpLayout) -> None:
    """Each group writes, reads and shows only its own points."""
    await start(dut)
    dots = 0
    value = 0
    for g, members in enumerate(layout.groups):
        digit_word = 0
        dp_word = 0
        for k, digit in enumerate(members):
            nibble = (g * 5 + k * 3 + 2) & 0xF
            digit_word |= nibble << (4 * k)
            value |= nibble << (4 * digit)
            if (g + k) % 2 == 0:
                dp_word |= 1 << k
                dots |= 1 << digit
        await core_write(dut, digit_word, g * GROUP_WORDS)
        await core_write(dut, 0xFFFF_FF00 | dp_word, g * GROUP_WORDS + DP_WORD)
        check_equal(int(dut.o_dp.value), dots, f"o_dp after group {g}")
        check_equal(
            int(dut.o_hex.value),
            expected_hex(layout, value, dots),
            f"segments after group {g}",
        )
        check_equal(
            await core_read(dut, g * GROUP_WORDS + DP_WORD),
            dp_word,
            f"read of the points of group {g}",
        )
        check_equal(
            await core_read(dut, g * GROUP_WORDS),
            digit_word,
            f"word 0 of group {g} unchanged",
        )
    check_equal(int(dut.o_value.value), value, "digit values untouched")


async def check_dp_lit_and_off(dut: Dut, layout: DpLayout) -> None:
    """Light and clear a point, leaving the digit value alone."""
    await start(dut)
    first = layout.groups[0]
    await core_write(dut, 0x7, 0)
    for digit in first:
        check_equal(
            (int(dut.o_hex.value) >> (DIGIT_BITS * digit + 7)) & 1,
            1 if layout.active_low else 0,
            f"point of digit {digit} off after reset",
        )
    await core_write(dut, 1, DP_WORD)
    pin = (int(dut.o_hex.value) >> (DIGIT_BITS * first[0] + 7)) & 1
    check_equal(pin, 0 if layout.active_low else 1, "point lit")
    await core_write(dut, 0, DP_WORD)
    pin = (int(dut.o_hex.value) >> (DIGIT_BITS * first[0] + 7)) & 1
    check_equal(pin, 1 if layout.active_low else 0, "point off again")


def check_blank_points(dut: Dut, layout: DpLayout, dots: int) -> None:
    """Check that only digits of a group have a point bit."""
    for digit in range(layout.digits):
        want = 1 if digit in layout.listed() else 0
        check_equal((dots >> digit) & 1, want, f"point of digit {digit}")
        if digit not in layout.listed():
            pins = (int(dut.o_hex.value) >> (DIGIT_BITS * digit)) & 0xFF
            check_equal(
                pins,
                0xFF if layout.active_low else 0,
                f"blank digit {digit} keeps its point off",
            )


async def check_missing_groups(dut: Dut, layout: DpLayout) -> None:
    """Check that missing groups and other words are silent."""
    dots = int(dut.o_dp.value)
    for g in range(len(layout.groups), 16):
        await core_write(dut, 0xFFFF_FFFF, g * GROUP_WORDS + DP_WORD)
        check_equal(
            await core_read(dut, g * GROUP_WORDS + DP_WORD),
            0,
            f"missing group {g}",
        )
    check_equal(int(dut.o_dp.value), dots, "missing groups ignored")
    for word in range(2, GROUP_WORDS):
        check_equal(await core_read(dut, word), 0, f"word {word} of group 0")


async def check_host_and_reset(dut: Dut, layout: DpLayout) -> None:
    """Check the host leaves points alone and reset clears them."""
    dots = int(dut.o_dp.value)
    bits = 4 * layout.digits
    await jtag.scan(dut, (1 << bits) | ((1 << bits) - 1), bits + 1)
    for _ in range(6):
        await core_read(dut, 0)
    check_equal(int(dut.o_dp.value), dots, "the host does not write points")
    dut.i_rst.value = 1
    await core_read(dut, 0)
    dut.i_rst.value = 0
    await core_read(dut, 0)
    check_equal(int(dut.o_dp.value), 0, "reset clears the points")


async def check_dp_silent(dut: Dut, layout: DpLayout) -> None:
    """Check blank digits, missing groups, host and reset."""
    await start(dut)
    for g in range(len(layout.groups)):
        await core_write(dut, 0xFFFF_FFFF, g * GROUP_WORDS + DP_WORD)
    check_blank_points(dut, layout, int(dut.o_dp.value))
    await check_missing_groups(dut, layout)
    await check_host_and_reset(dut, layout)


def tests(layout: DpLayout) -> dict[str, object]:
    """Build the cocotb tests of a layout, for a thin test module.

    Parameters
    ----------
    layout : DpLayout
        The layout and polarity the tests check.

    Returns
    -------
    dict[str, object]
        The tests by name, for the namespace of the test module.
    """

    @cocotb.test()
    async def test_dp_groups(dut: Dut) -> None:
        """Each group writes, reads and shows only its own points."""
        check_equal(len(dut.o_hex), DIGIT_BITS * layout.digits, "o_hex width")
        await check_dp_groups(dut, layout)

    @cocotb.test()
    async def test_dp_lit_and_off(dut: Dut) -> None:
        """Light and clear a point, leaving the digit value alone."""
        await check_dp_lit_and_off(dut, layout)

    @cocotb.test()
    async def test_dp_silent(dut: Dut) -> None:
        """Check blank digits, missing groups and reset."""
        await check_dp_silent(dut, layout)

    return {
        "test_dp_groups": test_dp_groups,
        "test_dp_lit_and_off": test_dp_lit_and_off,
        "test_dp_silent": test_dp_silent,
    }
