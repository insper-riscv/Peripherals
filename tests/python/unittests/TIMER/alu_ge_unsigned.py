"""ALU_GE_UNSIGNED: the unsigned greater-or-equal comparator."""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import Prng
from tests.python.utils.check import check
from tests.python.utils.dut import AluGeDut

WIDTH = 32
MAX = (1 << WIDTH) - 1
RANDOM_VECTORS = 200
SEED = 0x5EED


async def _compare(dut: AluGeDut, left: int, right: int) -> int:
    """Apply two operands and return the comparison result.

    Parameters
    ----------
    dut : AluGeDut
        The design under test.
    left : int
        First operand.
    right : int
        Second operand.

    Returns
    -------
    int
        The value of the greater-or-equal output.
    """
    dut.i_source_1.value = left
    dut.i_source_2.value = right
    await Timer(1, unit="ns")
    return int(dut.o_ge.value)


@cocotb.test()
async def test_equal_operands_are_greater_or_equal(dut: AluGeDut) -> None:
    """Equal operands give one, including the extremes."""
    for value in (0, 1, 0x7FFFFFFF, 0x80000000, MAX):
        result = await _compare(dut, value, value)
        check(result == 1, f"{value:#x} >= {value:#x}")


@cocotb.test()
async def test_neighbours_across_the_boundary(dut: AluGeDut) -> None:
    """One above gives one and one below gives zero."""
    for value in (1, 0x100, 0x7FFFFFFF, 0x80000000, MAX):
        above = await _compare(dut, value, value - 1)
        below = await _compare(dut, value - 1, value)
        check(above == 1, f"{value:#x} >= {value - 1:#x}")
        check(below == 0, f"{value - 1:#x} >= {value:#x}")


@cocotb.test()
async def test_comparison_is_unsigned(dut: AluGeDut) -> None:
    """A set most significant bit makes the operand the larger one."""
    check(await _compare(dut, 0x80000000, 1) == 1, "0x80000000 >= 1")
    check(await _compare(dut, 1, 0x80000000) == 0, "1 >= 0x80000000")
    check(await _compare(dut, MAX, 0) == 1, "MAX >= 0")
    check(await _compare(dut, 0, MAX) == 0, "0 >= MAX")


@cocotb.test()
async def test_single_bit_decides(dut: AluGeDut) -> None:
    """The highest differing bit decides the result."""
    for bit in range(WIDTH):
        high = 1 << bit
        low = high - 1
        check(await _compare(dut, high, low) == 1, f"bit {bit}: high")
        check(await _compare(dut, low, high) == 0, f"bit {bit}: low")


@cocotb.test()
async def test_random_pairs_match_the_integer_comparison(
    dut: AluGeDut,
) -> None:
    """Pseudo-random pairs agree with Python integer comparison."""
    prng = Prng(SEED)
    for _ in range(RANDOM_VECTORS):
        left = prng.getrandbits(WIDTH)
        right = prng.getrandbits(WIDTH)
        result = await _compare(dut, left, right)
        check(result == int(left >= right), f"{left:#x} vs {right:#x}")
