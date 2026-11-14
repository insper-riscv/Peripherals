"""Infrared receiver with a FIFO of two frames: overflow."""

import cocotb

from tests.python.unittests.IR import nec
from tests.python.unittests.IR.ir_receiver import eq, level, send, start, word
from tests.python.unittests.IR.registers import (
    CTRL,
    CTRL_EN,
    DATA,
    STAT_FULL,
    STAT_OVERFLOW,
    STATUS,
)
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import IrDut

DEPTH = 2


@cocotb.test()
async def test_overflow(dut: IrDut) -> None:
    """The frame that finds the FIFO full is lost and flagged."""
    await start(dut)
    for index in range(DEPTH + 1):
        await send(dut, nec.frame_levels(nec.frame_bytes(index, 0x10, False)))
    eq(await level(dut), DEPTH, "level")
    status = await bus.read(dut, STATUS)
    check(status & STAT_FULL != 0, "full")
    check(status & STAT_OVERFLOW != 0, "overflow flag")
    for index in range(DEPTH):
        eq(await bus.read(dut, DATA), word(index, 0x10), f"frame {index}")
    eq(await bus.read(dut, DATA), 0, "third frame was lost")
    await bus.write(dut, STATUS, STAT_OVERFLOW)
    status = await bus.read(dut, STATUS)
    eq(status & STAT_OVERFLOW, 0, "flag cleared")
    await bus.write(dut, CTRL, CTRL_EN)
