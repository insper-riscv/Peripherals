"""CLINT_MTIME: a 64-bit counter in two halves, coherent reads."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import Prng
from tests.python.unittests.CLINT.registers import MASK32, MASK64
from tests.python.utils.check import check
from tests.python.utils.dut import ClintMtimeDut

COUNTS = 5
RANDOM_STEPS = 600
SEED = 0xC11D7


async def start(dut: ClintMtimeDut) -> None:
    """Start the clock and reset the counter.

    Parameters
    ----------
    dut : ClintMtimeDut
        The design under test.
    """
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_inc.value = 0
    dut.i_we_lo.value = 0
    dut.i_we_hi.value = 0
    dut.i_wdata.value = 0
    dut.i_rst.value = 1
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0


def value(dut: ClintMtimeDut) -> int:
    """Return the 64-bit value the counter shows.

    Parameters
    ----------
    dut : ClintMtimeDut
        The design under test.

    Returns
    -------
    int
        The high half and the low half together.
    """
    return (int(dut.o_hi.value) << 32) | int(dut.o_lo.value)


async def step(
    dut: ClintMtimeDut,
    inc: int,
    we_lo: int,
    we_hi: int,
    wdata: int,
) -> None:
    """Run one clock edge with the given inputs.

    Parameters
    ----------
    dut : ClintMtimeDut
        The design under test.
    inc : int
        Increment input.
    we_lo : int
        Write of the low half.
    we_hi : int
        Write of the high half.
    wdata : int
        Write data.
    """
    dut.i_inc.value = inc
    dut.i_we_lo.value = we_lo
    dut.i_we_hi.value = we_hi
    dut.i_wdata.value = wdata
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


def model_next(
    model: int, inc: int, we_lo: int, we_hi: int, wdata: int
) -> int:
    """Return the ideal counter value after one edge.

    Parameters
    ----------
    model : int
        The value before the edge.
    inc : int
        Increment input.
    we_lo : int
        Write of the low half.
    we_hi : int
        Write of the high half.
    wdata : int
        Write data.

    Returns
    -------
    int
        The value after the edge.
    """
    lo = wdata if we_lo else (model + inc) & MASK32
    carry = int(inc and not we_lo and (model & MASK32) == MASK32)
    hi = wdata if we_hi else model >> 32
    return (((hi + carry) & MASK32) << 32) | lo


@cocotb.test()
async def test_reset_and_count(dut: ClintMtimeDut) -> None:
    """Zero after reset, then one per increment."""
    await start(dut)
    check(value(dut) == 0)
    for k in range(1, COUNTS + 1):
        await step(dut, 1, 0, 0, 0)
        check(value(dut) == k)
    await step(dut, 0, 0, 0, 0)
    check(value(dut) == COUNTS, "no increment, no change")


@cocotb.test()
async def test_carry_into_the_high_half(dut: ClintMtimeDut) -> None:
    """The wrap of the low half shows in the high half at once."""
    await start(dut)
    await step(dut, 0, 0, 1, 2)
    await step(dut, 0, 1, 0, MASK32)
    check(value(dut) == (2 << 32) | MASK32)
    await step(dut, 1, 0, 0, 0)
    check(value(dut) == 3 << 32, f"{value(dut):#x}")
    await step(dut, 1, 0, 0, 0)
    check(value(dut) == (3 << 32) | 1, f"{value(dut):#x}")


@cocotb.test()
async def test_random_steps_follow_the_ideal_counter(
    dut: ClintMtimeDut,
) -> None:
    """Random increments and writes, including near the wrap."""
    await start(dut)
    prng = Prng(SEED)
    model = 0
    near_wrap = (0, 0xFFFFFFFF, 0xFFFFFFFE, 0x7FFFFFFF)
    for _ in range(RANDOM_STEPS):
        inc = prng.getrandbits(1)
        we_lo = int(prng.getrandbits(3) == 0)
        we_hi = int(prng.getrandbits(3) == 0)
        pick = prng.getrandbits(2)
        wdata = (
            near_wrap[pick] if prng.getrandbits(1) else prng.getrandbits(32)
        )
        model = model_next(model, inc, we_lo, we_hi, wdata)
        await step(dut, inc, we_lo, we_hi, wdata)
        check(value(dut) == model & MASK64, f"{value(dut):#x} {model:#x}")
