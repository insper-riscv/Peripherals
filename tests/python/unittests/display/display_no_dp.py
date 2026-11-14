"""The default display (has_dp false) is unchanged.

o_hex keeps 7 bits per digit, word 1 of a group reads zero and ignores
writes, and o_dp stays zero.
"""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.display.patterns import PATTERNS
from tests.python.unittests.display.seg_display import (
    core_read,
    core_write,
    start,
)
from tests.python.unittests.dut import Dut

DIGITS = 6


@cocotb.test()
async def test_without_dp_the_display_is_unchanged(dut: Dut) -> None:
    """Seven bits per digit; the point word is silent."""
    await start(dut)
    check_equal(len(dut.o_hex), 7 * DIGITS, "o_hex width")
    await core_write(dut, 0x543210)
    before = int(dut.o_hex.value)
    expected = 0
    for n in range(DIGITS):
        expected |= PATTERNS[n] << (7 * n)
    check_equal(before, expected, "segments")
    await core_write(dut, 0x3F, 1)
    check_equal(await core_read(dut, 1), 0, "word 1 reads zero")
    check_equal(int(dut.o_hex.value), before, "write to word 1 ignored")
    check_equal(int(dut.o_dp.value), 0, "o_dp stays zero")
