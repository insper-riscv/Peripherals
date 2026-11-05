"""CLINT with tick_cycles = 4: mtime adds one every four cycles."""

import itertools

import cocotb

from tests.python.unittests.CLINT.registers import MTIME_LO
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import ClintDut

TICK_CYCLES = 4
READS = 24
MIN_CHANGES = 4


@cocotb.test()
async def test_mtime_adds_one_every_tick_cycles(dut: ClintDut) -> None:
    """The low half changes by one exactly every four cycles."""
    await bus.reset(dut)
    values = [await bus.read(dut, MTIME_LO) for _ in range(READS)]
    changes = [k for k in range(1, READS) if values[k] != values[k - 1]]
    check(len(changes) >= MIN_CHANGES, f"changes {changes}")
    gaps = {b - a for a, b in itertools.pairwise(changes)}
    check(gaps == {TICK_CYCLES}, f"gaps {gaps}")
    check(values[-1] - values[0] == len(changes), f"{values}")
