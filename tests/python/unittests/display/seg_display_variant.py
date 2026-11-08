"""The display register with three digits and active-high segments.

seg_display with digits 3 and active_low false: a register of 12 bits,
a scan of 13 bits, and segments that are the complement of the board
patterns.
"""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.display.patterns import PATTERNS
from tests.python.unittests.display.seg_display import (
    core_read,
    core_write,
    post_edge,
    start,
)
from tests.python.unittests.dut import Dut
from tests.python.utils import jtag

DIGITS = 3
VALUE_BITS = 4 * DIGITS
SEGMENT_MASK = (1 << (7 * DIGITS)) - 1


def expected_hex(value: int) -> int:
    """Return the active-high segment pattern expected for a value."""
    out = 0
    for n in range(DIGITS):
        out |= PATTERNS[(value >> (4 * n)) & 0xF] << (7 * n)
    return ~out & SEGMENT_MASK


async def scan(dut: Dut, value: int | None = None) -> int:
    """One scan of the register: writes `value` if given, reads."""
    word = 0 if value is None else (1 << VALUE_BITS) | value
    out = await jtag.scan(dut, word, VALUE_BITS + 1)
    return out & ((1 << VALUE_BITS) - 1)


@cocotb.test()
async def test_segments_are_active_high_and_per_position(dut: Dut):
    """Each digit lights its own segments at the high level."""
    await start(dut)
    await core_write(dut, 0xA5C)
    check_equal(int(dut.o_hex.value), expected_hex(0xA5C))
    check_equal(int(dut.o_value.value), 0xA5C)


@cocotb.test()
async def test_register_keeps_only_the_digits_it_has(dut: Dut):
    """Twelve bits are kept and read back."""
    await start(dut)
    await core_write(dut, 0xFFFFF123)
    check_equal(await core_read(dut), 0x123)


@cocotb.test()
async def test_host_scan_has_one_bit_per_digit_plus_the_write_bit(dut: Dut):
    """The host writes and reads a 13-bit scan."""
    await start(dut)
    check_equal(await scan(dut, 0x4B2), 0)
    for _ in range(6):
        await post_edge(dut)
    check_equal(int(dut.o_value.value), 0x4B2)
    check_equal(await scan(dut), 0x4B2)
