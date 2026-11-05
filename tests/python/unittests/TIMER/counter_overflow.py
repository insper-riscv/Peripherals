"""COUNTER_OVERFLOW: overflow when the count reaches the top."""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import Prng
from tests.python.utils.check import check
from tests.python.utils.dut import CounterOverflowDut

WIDTH = 32
MAX = (1 << WIDTH) - 1
RANDOM_VECTORS = 200
SEED = 0xC0DE


async def _overflow(dut: CounterOverflowDut, count: int, top: int) -> int:
    """Apply a count and a top value and return the overflow.

    Parameters
    ----------
    dut : CounterOverflowDut
        The design under test.
    count : int
        Current count.
    top : int
        Top value.

    Returns
    -------
    int
        The value of the overflow output.
    """
    dut.i_counter_value.value = count
    dut.i_top_value.value = top
    await Timer(1, unit="ns")
    return int(dut.o_overflow.value)


@cocotb.test()
async def test_no_overflow_below_the_top(dut: CounterOverflowDut) -> None:
    """A count under the top does not overflow."""
    for top in (1, 10, 0x80000000, MAX):
        result = await _overflow(dut, top - 1, top)
        check(result == 0, f"count {top - 1:#x} under top {top:#x}")


@cocotb.test()
async def test_overflow_at_the_top(dut: CounterOverflowDut) -> None:
    """A count equal to the top overflows."""
    for top in (0, 1, 10, 0x80000000, MAX):
        result = await _overflow(dut, top, top)
        check(result == 1, f"count at top {top:#x}")


@cocotb.test()
async def test_overflow_above_the_top(dut: CounterOverflowDut) -> None:
    """A count over the top overflows too."""
    for top in (0, 1, 10, 0x7FFFFFFF, MAX - 1):
        result = await _overflow(dut, top + 1, top)
        check(result == 1, f"count over top {top:#x}")


@cocotb.test()
async def test_random_pairs_match_the_integer_comparison(
    dut: CounterOverflowDut,
) -> None:
    """Pseudo-random pairs agree with count >= top."""
    prng = Prng(SEED)
    for _ in range(RANDOM_VECTORS):
        count = prng.getrandbits(WIDTH)
        top = prng.getrandbits(WIDTH)
        result = await _overflow(dut, count, top)
        check(result == int(count >= top), f"{count:#x} vs {top:#x}")
