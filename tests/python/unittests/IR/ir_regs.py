"""Registers of the infrared receiver driven without the decoder."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.dut import Dut
from tests.python.unittests.IR.registers import (
    CTRL,
    CTRL_EN,
    CTRL_ERR_IE,
    CTRL_EXT_EN,
    CTRL_FLUSH,
    CTRL_FRAME_IE,
    CTRL_RAW_IE,
    DATA,
    FRAME_EXT,
    RAW_MARK,
    RAW_SPACE,
    STAT_FRAME_ERR,
    STAT_FULL,
    STAT_LEVEL_SHIFT,
    STAT_LINE,
    STAT_NOT_EMPTY,
    STAT_OVERFLOW,
    STAT_RAW_NEW,
    STATUS,
)
from tests.python.utils import bus
from tests.python.utils.check import check

DEPTH = 2
MARK_WIDTH = 1234
SPACE_WIDTH = 4321


async def start(dut: Dut) -> None:
    """Reset the registers with every decoder input idle.

    Parameters
    ----------
    dut : Dut
        The design under test.
    """
    for name in (
        "i_frame_valid",
        "i_repeat_f",
        "i_extended_f",
        "i_error_f",
        "i_event",
        "i_event_mark",
        "i_line_active",
    ):
        getattr(dut, name).value = 0
    dut.i_address_f.value = 0
    dut.i_command_f.value = 0
    dut.i_width.value = 0
    await bus.reset(dut)


async def pulse(dut: Dut, name: str) -> None:
    """Raise one decoder input for a cycle.

    Parameters
    ----------
    dut : Dut
        The design under test.
    name : str
        Name of the input port.
    """
    getattr(dut, name).value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    getattr(dut, name).value = 0


async def push(dut: Dut, address: int, command: int, flags: int = 0) -> None:
    """Hand one frame to the registers.

    Parameters
    ----------
    dut : Dut
        The design under test.
    address : int
        Address of the frame.
    command : int
        Command of the frame.
    flags : int
        1 for a repeat, 2 for an extended frame.
    """
    dut.i_address_f.value = address
    dut.i_command_f.value = command
    dut.i_repeat_f.value = flags & 1
    dut.i_extended_f.value = (flags >> 1) & 1
    await pulse(dut, "i_frame_valid")


@cocotb.test()
async def test_reset_and_control(dut: Dut) -> None:
    """Reset values, control read-back and the enable outputs."""
    await start(dut)
    check(await bus.read(dut, CTRL) == CTRL_EXT_EN, "reset control")
    check(int(dut.o_enable.value) == 0 and int(dut.o_ext_en.value) == 1, "o")
    value = CTRL_EN | CTRL_FRAME_IE | CTRL_ERR_IE | CTRL_RAW_IE
    await bus.write(dut, CTRL, value | CTRL_FLUSH)
    check(await bus.read(dut, CTRL) == value, "flush bit reads zero")
    check(int(dut.o_enable.value) == 1 and int(dut.o_ext_en.value) == 0, "o")
    for address in (5, 6, 7):
        check(await bus.read(dut, address) == 0, f"unmapped {address}")


@cocotb.test()
async def test_frames_status_irq(dut: Dut) -> None:
    """Frames, status fields, overflow and the interrupt masks."""
    await start(dut)
    await push(dut, 0x1234, 0x56, 2)
    status = await bus.read(dut, STATUS)
    check(status & STAT_NOT_EMPTY != 0, "not empty")
    check((status >> STAT_LEVEL_SHIFT) & 0xFF == 1, "level")
    check(int(dut.o_irq.value) == 0, "masked")
    await bus.write(dut, CTRL, CTRL_FRAME_IE)
    await bus.cycles(dut, 1)
    check(int(dut.o_irq.value) == 1, "frame irq")
    await push(dut, 0x0001, 0x02)
    await push(dut, 0x0002, 0x03)
    status = await bus.read(dut, STATUS)
    check(status & STAT_FULL != 0 and status & STAT_OVERFLOW != 0, "full")
    check(int(dut.o_irq.value) == 1, "still raised")
    word = await bus.read(dut, DATA)
    check(word == 0x1234 | (0x56 << 16) | FRAME_EXT, f"head {word:#x}")
    await bus.write(dut, STATUS, STAT_OVERFLOW)
    status = await bus.read(dut, STATUS)
    check(status & STAT_OVERFLOW == 0, "overflow cleared")
    check(await bus.read(dut, DATA) == 0x1 | (0x02 << 16), "second")
    check(int(dut.o_irq.value) == 0, "empty again")


@cocotb.test()
async def test_error_and_raw(dut: Dut) -> None:
    """Sticky error and raw flags, raw widths and their masks."""
    await start(dut)
    await pulse(dut, "i_error_f")
    status = await bus.read(dut, STATUS)
    check(status & STAT_FRAME_ERR != 0, "error")
    await bus.write(dut, CTRL, CTRL_ERR_IE)
    await bus.cycles(dut, 1)
    check(int(dut.o_irq.value) == 1, "error irq")
    await bus.write(dut, STATUS, STAT_FRAME_ERR)
    check(int(dut.o_irq.value) == 0, "error irq cleared")
    dut.i_width.value = MARK_WIDTH
    dut.i_event_mark.value = 1
    await pulse(dut, "i_event")
    dut.i_width.value = SPACE_WIDTH
    dut.i_event_mark.value = 0
    await pulse(dut, "i_event")
    check(await bus.read(dut, RAW_MARK) == MARK_WIDTH, "raw mark")
    check(await bus.read(dut, RAW_SPACE) == SPACE_WIDTH, "raw space")
    status = await bus.read(dut, STATUS)
    check(status & STAT_RAW_NEW != 0, "raw new")
    check(int(dut.o_irq.value) == 0, "raw masked")
    await bus.write(dut, CTRL, CTRL_RAW_IE)
    await bus.cycles(dut, 1)
    check(int(dut.o_irq.value) == 1, "raw irq")
    await bus.write(dut, STATUS, STAT_RAW_NEW)
    check(int(dut.o_irq.value) == 0, "raw irq cleared")
    dut.i_line_active.value = 1
    await Timer(1, unit="ns")
    status = await bus.read(dut, STATUS)
    check(status & STAT_LINE != 0, "line level")
