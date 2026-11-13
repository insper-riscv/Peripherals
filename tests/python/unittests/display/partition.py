"""Shared checks of the seg_display groups (seg_display_tb), by layout.

A layout says how many digits the display has and which digits each
group lists, in the written order. Digit k of a group is at bits 4k+3
to 4k of word 0 of the group; a digit that is in no group stays blank.
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

GROUP_WORDS = 16
FULL_DIGITS = 8
UPPER_NIBBLE = 0xF << 28
BLANK = 0x7F


@dataclass(frozen=True)
class Layout:
    """Digit layout of one display.

    Attributes
    ----------
    digits : int
        Digits of the display.
    groups : tuple[tuple[int, ...], ...]
        Digit indices of each group, in the written order.
    """

    digits: int
    groups: tuple[tuple[int, ...], ...]

    def listed(self) -> set[int]:
        """Return the digits that are in some group."""
        return {d for group in self.groups for d in group}


def segments(layout: Layout, value: int) -> int:
    """Return the expected o_hex for a stored value."""
    out = 0
    for n in range(layout.digits):
        pattern = PATTERNS[(value >> (4 * n)) & 0xF]
        if n not in layout.listed():
            pattern = BLANK
        out |= pattern << (7 * n)
    return out


async def check_groups(dut: Dut, layout: Layout) -> None:
    """Each group writes and reads only its own digits."""
    await start(dut)
    check_equal(int(dut.o_hex.value), segments(layout, 0), "after reset")
    stored = 0
    for g, members in enumerate(layout.groups):
        word = 0
        for k, digit in enumerate(members):
            nibble = (g * 5 + k * 3 + 1) & 0xF
            word |= nibble << (4 * k)
            stored &= ~(0xF << (4 * digit))
            stored |= nibble << (4 * digit)
        junk = UPPER_NIBBLE if len(members) < FULL_DIGITS else 0
        await core_write(dut, 0xFFFF_FFFF & (word | junk), g * GROUP_WORDS)
        check_equal(int(dut.o_value.value), stored, f"value after group {g}")
        check_equal(
            int(dut.o_hex.value),
            segments(layout, stored),
            f"segments after group {g}",
        )
        got = await core_read(dut, g * GROUP_WORDS)
        check_equal(got, word, f"read of group {g}")


async def check_unused(dut: Dut, layout: Layout) -> None:
    """Other words, missing groups and blank digits stay silent."""
    await start(dut)
    count = len(layout.groups)
    for g in range(count):
        await core_write(dut, 0xFFFF_FFFF, g * GROUP_WORDS)
        for word in range(1, GROUP_WORDS):
            check_equal(
                await core_read(dut, g * GROUP_WORDS + word),
                0,
                f"group {g} word {word}",
            )
    stored = int(dut.o_value.value)
    for g in range(count, 16):
        await core_write(dut, 0xFFFF_FFFF, g * GROUP_WORDS)
        check_equal(
            await core_read(dut, g * GROUP_WORDS), 0, f"missing group {g}"
        )
    check_equal(
        int(dut.o_value.value), stored, "writes to missing groups are ignored"
    )
    for g in range(count):
        await core_write(dut, 0, g * GROUP_WORDS + 1)
    check_equal(
        int(dut.o_value.value), stored, "writes to other words are ignored"
    )
    for digit in range(layout.digits):
        if digit in layout.listed():
            continue
        hex_value = int(dut.o_hex.value)
        check_equal(
            (hex_value >> (7 * digit)) & 0x7F, BLANK, f"digit {digit} blank"
        )


def tests(layout: Layout) -> dict[str, object]:
    """Build the cocotb tests of a layout, for a thin test module.

    Parameters
    ----------
    layout : Layout
        The digit layout the tests check.

    Returns
    -------
    dict[str, object]
        The tests by name, for the namespace of the test module.
    """

    @cocotb.test()
    async def test_groups(dut: Dut) -> None:
        """Each group writes and reads only its own digits."""
        await check_groups(dut, layout)

    @cocotb.test()
    async def test_unused(dut: Dut) -> None:
        """Other words, missing groups and blank digits stay silent."""
        await check_unused(dut, layout)

    return {"test_groups": test_groups, "test_unused": test_unused}
